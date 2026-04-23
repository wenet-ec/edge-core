# edge_agent/lib/edge_agent/proxy_servers/socks5/handler.ex
defmodule EdgeAgent.ProxyServers.Socks5.Handler do
  @moduledoc """
  Ranch protocol handler for agent SOCKS5 proxy.

  Protocol per RFC 1928 (SOCKS5), RFC 1929 (Username/Password Auth).

  All wire parsing is delegated to `Socks5.Codec`. Connection reads use
  `BufferedReader` so fragmented deliveries are handled correctly.
  """

  @behaviour :ranch_protocol

  alias EdgeAgent.ProxyServers.Authentication
  alias EdgeAgent.ProxyServers.Config
  alias EdgeAgent.ProxyServers.ErrorHandler
  alias EdgeAgent.ProxyServers.Socks5.Codec, as: Socks5Codec
  alias EdgeAgent.ProxyServers.Transport.BufferedReader
  alias EdgeAgent.ProxyServers.Transport.DestinationValidator
  alias EdgeAgent.ProxyServers.Transport.Forwarder
  alias EdgeAgent.ProxyServers.Transport.TunnelRegistry

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

    start_time = System.monotonic_time(:millisecond)

    result =
      case handle_socks5_handshake(socket, transport) do
        :ok ->
          :ok

        {:error, reason} ->
          _ = ErrorHandler.log_error(reason, %{protocol: :socks5})
          transport.close(socket)
          {:error, reason}
      end

    duration = System.monotonic_time(:millisecond) - start_time

    {conn_result, telemetry_meta} =
      case result do
        :ok ->
          {:success, %{result: :success, protocol: :socks5}}

        {:error, :auth_failed} ->
          {:auth_failed, %{result: :auth_failed, protocol: :socks5}}

        {:error, reason} ->
          {:failure, reason |> ErrorHandler.telemetry_metadata(:socks5) |> Map.put(:result, :failure)}
      end

    :telemetry.execute(
      [:edge_agent, :proxy, :socks5, :connection],
      %{count: 1, total: 1},
      telemetry_meta
    )

    if conn_result == :success do
      :telemetry.execute(
        [:edge_agent, :proxy, :session, :duration],
        %{duration: duration},
        %{protocol: :socks5}
      )
    end

    result
  end

  defp handle_socks5_handshake(socket, transport) do
    with {:ok, methods, leftover0} <- read_greeting(socket),
         :ok <- send_auth_method(socket, transport, methods),
         {:ok, leftover1} <- handle_authentication(socket, transport, leftover0),
         {:ok, target_host, target_port, _leftover2} <- read_connect_request(socket, transport, leftover1) do
      establish_tunnel(socket, transport, target_host, target_port)
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
        case Authentication.authenticate(username, password) do
          :ok ->
            Logger.info("SOCKS5 authentication successful for user: #{username}")
            transport.send(socket, Socks5Codec.encode_auth_reply(0))
            {:ok, rest}

          {:error, _reason} ->
            Logger.warning("SOCKS5 authentication failed for user: #{username}")
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
        Logger.info("SOCKS5 CONNECT to #{host}:#{port}")
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

  defp establish_tunnel(socket, transport, target_host, target_port) do
    metadata = %{protocol: :socks5, target_host: target_host, target_port: target_port}

    case DestinationValidator.resolve_and_validate(target_host, target_port) do
      {:ok, ip_tuple} ->
        case :gen_tcp.connect(
               ip_tuple,
               target_port,
               [:binary, packet: :raw, active: false],
               Config.connection_timeout()
             ) do
          {:ok, target_socket} ->
            send_success_reply(socket, transport, target_socket)
            :ok = TunnelRegistry.register(metadata)

            try do
              Forwarder.forward(socket, target_socket, metadata)
            after
              TunnelRegistry.unregister()
            end

          {:error, reason} ->
            send_failure_reply(socket, transport, ErrorHandler.socks5_reply_code(reason))
            {:error, reason}
        end

      {:error, reason} ->
        :telemetry.execute(
          [:edge_agent, :proxy, :socks5, :blocked],
          %{count: 1},
          %{reason: reason, host: target_host, port: target_port}
        )

        send_failure_reply(socket, transport, ErrorHandler.socks5_reply_code(reason))
        {:error, reason}
    end
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
