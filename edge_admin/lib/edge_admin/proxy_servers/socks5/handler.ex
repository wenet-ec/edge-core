# edge_admin/lib/edge_admin/proxy_servers/socks5/handler.ex
defmodule EdgeAdmin.ProxyServers.Socks5.Handler do
  @moduledoc """
  Ranch protocol handler for SOCKS5 proxy.

  Protocol per RFC 1928 (SOCKS5), RFC 1929 (Username/Password Auth).

  All wire parsing is delegated to `Socks5Codec`. Connection reads use
  `BufferedReader` so fragmented deliveries are handled correctly.
  """

  @behaviour :ranch_protocol

  alias EdgeAdmin.ProxyServers.Authentication
  alias EdgeAdmin.ProxyServers.Config
  alias EdgeAdmin.ProxyServers.ErrorHandler
  alias EdgeAdmin.ProxyServers.Socks5.Codec, as: Socks5Codec
  alias EdgeAdmin.ProxyServers.Transport.BufferedReader
  alias EdgeAdmin.ProxyServers.Transport.TunnelRegistry
  alias EdgeAdmin.ProxyServers.Tunnel.TcpTunnel

  require Logger

  @auth_method_userpass 2
  @auth_method_none_acceptable 0xFF

  @cmd_connect 1

  @reply_success 0

  @impl true
  def start_link(ref, transport, opts) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [ref, transport, opts])
    {:ok, pid}
  end

  def init(ref, transport, _opts) do
    {:ok, socket} = :ranch.handshake(ref)
    {:ok, {client_ip, client_port}} = :inet.peername(socket)
    Logger.info("SOCKS5 client connected from #{:inet.ntoa(client_ip)}:#{client_port}")

    start_time = System.monotonic_time()
    result = handle_socks5_handshake(socket, transport)
    duration_ms = System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

    emit_telemetry(result, duration_ms)

    case result do
      {:ok, _routing_mode, _proxy_mode, _cluster_name} -> :ok
      _ -> transport.close(socket)
    end
  end

  defp emit_telemetry({:ok, routing_mode, proxy_mode, cluster_name}, duration_ms) do
    :telemetry.execute(
      [:edge_admin, :proxy, :connection],
      %{count: 1, total: 1},
      %{protocol: :socks5, result: :success, routing_mode: routing_mode, proxy_mode: proxy_mode, cluster: cluster_name}
    )

    :telemetry.execute(
      [:edge_admin, :proxy, :session, :duration],
      %{duration: duration_ms},
      %{protocol: :socks5, routing_mode: routing_mode, proxy_mode: proxy_mode, cluster: cluster_name}
    )
  end

  defp emit_telemetry({:error, :auth_failed}, _duration_ms) do
    :telemetry.execute([:edge_admin, :proxy, :auth_failure], %{count: 1, total: 1}, %{protocol: :socks5})

    :telemetry.execute(
      [:edge_admin, :proxy, :connection],
      %{count: 1, total: 1},
      %{protocol: :socks5, result: :auth_failed, routing_mode: :unknown, proxy_mode: :unknown, cluster: "unknown"}
    )
  end

  defp emit_telemetry({:error, reason}, _duration_ms) do
    _ = ErrorHandler.log_error(reason, %{protocol: :socks5})

    :telemetry.execute(
      [:edge_admin, :proxy, :connection],
      %{count: 1, total: 1},
      reason
      |> ErrorHandler.telemetry_metadata(:socks5)
      |> Map.merge(%{result: :failure, routing_mode: :unknown, proxy_mode: :unknown, cluster: "unknown"})
    )
  end

  defp handle_socks5_handshake(socket, transport) do
    with {:ok, methods, leftover0} <- read_greeting(socket),
         :ok <- send_auth_method(socket, transport, methods),
         {:ok, routing_mode, exit_node, leftover1} <- handle_authentication(socket, transport, leftover0),
         {:ok, target_host, target_port, _leftover2} <- read_connect_request(socket, transport, leftover1) do
      establish_tunnel(socket, transport, target_host, target_port, routing_mode, exit_node)
    end
  end

  defp read_greeting(socket) do
    BufferedReader.read_passive(socket, &Socks5Codec.parse_greeting/1, Config.read_timeout())
  end

  defp send_auth_method(socket, transport, client_methods) do
    if @auth_method_userpass in client_methods do
      transport.send(socket, Socks5Codec.encode_method_reply(@auth_method_userpass))
    else
      Logger.warning("SOCKS5 client doesn't support username/password authentication")
      transport.send(socket, Socks5Codec.encode_method_reply(@auth_method_none_acceptable))
      {:error, :no_acceptable_methods}
    end
  end

  defp handle_authentication(socket, transport, leftover) do
    case read_with_leftover(socket, &Socks5Codec.parse_auth_request/1, leftover) do
      {:ok, {username, password}, rest} ->
        case Authentication.authenticate_and_parse(username, password) do
          {:ok, :direct} ->
            transport.send(socket, Socks5Codec.encode_auth_reply(0))
            {:ok, :direct, nil, rest}

          {:ok, :chain, node} ->
            transport.send(socket, Socks5Codec.encode_auth_reply(0))
            {:ok, :chain, node, rest}

          {:error, _reason} ->
            transport.send(socket, Socks5Codec.encode_auth_reply(1))
            {:error, :auth_failed}
        end

      {:error, _} = err ->
        err
    end
  end

  defp read_connect_request(socket, transport, leftover) do
    case read_with_leftover(socket, &Socks5Codec.parse_connect_request/1, leftover) do
      {:ok, {@cmd_connect, host, port}, rest} ->
        {:ok, host, port, rest}

      {:ok, {cmd, _, _}, _} ->
        Logger.warning("Unsupported SOCKS5 command: #{cmd}")
        send_failure_reply(socket, transport, ErrorHandler.socks5_reply_code(:unsupported_command))
        {:error, :unsupported_command}

      {:error, {:unsupported_address_type, _}} = err ->
        send_failure_reply(socket, transport, ErrorHandler.socks5_reply_code(:unsupported_address_type))
        err

      {:error, _} = err ->
        err
    end
  end

  defp read_with_leftover(socket, parser, leftover) do
    case parser.(leftover) do
      {:ok, _, _} = ok ->
        ok

      {:error, _} = err ->
        err

      {:need_more, _} ->
        case :gen_tcp.recv(socket, 0, Config.read_timeout()) do
          {:ok, data} -> read_with_leftover(socket, parser, leftover <> data)
          {:error, _} = err -> err
        end
    end
  end

  defp establish_tunnel(socket, transport, target_host, target_port, routing_mode, exit_node) do
    opts = tunnel_opts(routing_mode, exit_node)
    proxy_mode = if routing_mode == :chain, do: :chain, else: :direct
    cluster_name = TcpTunnel.cluster_name_from_hostname(target_host) || "unknown"

    metadata = %{
      protocol: :socks5,
      target_host: target_host,
      target_port: target_port,
      routing_mode: routing_mode,
      cluster: cluster_name
    }

    case TcpTunnel.connect(target_host, target_port, self(), opts) do
      {:ok, {:local, target_socket}} ->
        send_success_reply(socket, transport, target_socket)
        :ok = TunnelRegistry.register(metadata)

        try do
          TcpTunnel.start_forwarding(socket, target_socket, metadata)
        after
          TunnelRegistry.unregister()
        end

        {:ok, :local, proxy_mode, cluster_name}

      {:ok, {:remote, proxy_pid}} ->
        send_success_reply(socket, transport, nil)
        transport.setopts(socket, active: true)
        :ok = TunnelRegistry.register(metadata)

        try do
          handle_remote_streaming(socket, transport, proxy_pid)
        after
          TunnelRegistry.unregister()
        end

        {:ok, :remote, proxy_mode, cluster_name}

      {:error, reason} ->
        send_failure_reply(socket, transport, ErrorHandler.socks5_reply_code(reason))
        {:error, reason}
    end
  end

  defp tunnel_opts(:direct, _exit_node), do: []
  defp tunnel_opts(:chain, exit_node), do: [exit_node: exit_node, protocol: :socks5]

  defp handle_remote_streaming(socket, transport, proxy_pid) do
    handle_remote_streaming(socket, transport, proxy_pid, Config.recv_timeout())
  end

  defp handle_remote_streaming(socket, transport, proxy_pid, timeout) do
    receive do
      {:tcp, ^socket, data} ->
        send(proxy_pid, {:send_to_target, data})
        handle_remote_streaming(socket, transport, proxy_pid, timeout)

      {:remote_target_data, ^proxy_pid, data} ->
        transport.send(socket, data)
        handle_remote_streaming(socket, transport, proxy_pid, timeout)

      {:remote_target_closed, ^proxy_pid} ->
        transport.close(socket)
        {:ok, :closed}

      {:remote_target_error, ^proxy_pid, _reason} ->
        transport.close(socket)
        {:ok, :closed}

      {:tcp_closed, ^socket} ->
        send(proxy_pid, :close)
        {:ok, :closed}

      {:tcp_error, ^socket, _reason} ->
        send(proxy_pid, :close)
        {:ok, :closed}

      {:drain, grace_ms} ->
        # Let in-flight bytes through, but no more than grace_ms.
        handle_remote_streaming(socket, transport, proxy_pid, min(timeout, grace_ms))
    after
      timeout ->
        send(proxy_pid, :close)
        transport.close(socket)
        {:ok, :closed}
    end
  end

  defp send_success_reply(socket, transport, nil) do
    transport.send(socket, Socks5Codec.encode_reply(@reply_success, nil, 0))
  end

  defp send_success_reply(socket, transport, target_socket) do
    {addr, port} =
      case :inet.sockname(target_socket) do
        {:ok, {a, p}} -> {a, p}
        _ -> {nil, 0}
      end

    transport.send(socket, Socks5Codec.encode_reply(@reply_success, addr, port))
  end

  defp send_failure_reply(socket, transport, reply_code) do
    transport.send(socket, Socks5Codec.encode_reply(reply_code, nil, 0))
  end
end
