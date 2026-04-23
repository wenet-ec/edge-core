# edge_admin/lib/edge_admin/proxy_servers/tunnel/tcp_tunnel.ex
defmodule EdgeAdmin.ProxyServers.Tunnel.TcpTunnel do
  @moduledoc """
  TCP tunnel for admin proxy forwarding.

  Connects to a target through either:

    1. Direct VPN path — dispatch via cluster-owning Gateway
    2. Proxy chaining — dial agent proxy and handshake through it

  Callers use this module in two phases:

    * `connect/5` returns a tunnel handle (local socket or remote proxy pid)
      without starting byte-forwarding. The caller can send the appropriate
      success response to the client first.
    * `start_forwarding/3` hands off to `Forwarder` (local) or expects the
      caller to run its own receive loop for the remote handle.
  """

  alias EdgeAdmin.EdgeClusters.Gateway
  alias EdgeAdmin.ProxyServers.Config
  alias EdgeAdmin.ProxyServers.ErrorHandler
  alias EdgeAdmin.ProxyServers.Socks5.Codec, as: Socks5Codec
  alias EdgeAdmin.ProxyServers.Transport.BufferedReader
  alias EdgeAdmin.ProxyServers.Transport.Forwarder

  require Logger

  @type handle ::
          {:local, :gen_tcp.socket()}
          | {:remote, pid()}

  @doc """
  Establish a tunnel to `target_host:target_port`.

  Options:
    * `:exit_node` — Node struct; when set, chain through that agent's proxy
    * `:protocol` — `:http` | `:socks5` (chain protocol, default `:http`)
    * `:initial_data` — bytes to send to the target immediately after connect

  Returns `{:ok, handle}` or `{:error, reason}`.
  """
  @spec connect(String.t(), 1..65_535, pid(), keyword()) :: {:ok, handle()} | {:error, term()}
  def connect(target_host, target_port, caller_pid, opts \\ []) do
    initial_data = Keyword.get(opts, :initial_data)

    case Keyword.get(opts, :exit_node) do
      nil ->
        connect_direct(target_host, target_port, caller_pid, initial_data)

      exit_node ->
        protocol = Keyword.get(opts, :protocol, :http)
        connect_via_agent_proxy(exit_node, target_host, target_port, caller_pid, initial_data, protocol)
    end
  end

  @doc """
  Start bidirectional forwarding for a local handle. Blocks until both sides close.

  For remote handles, the caller runs its own streaming loop — see
  `handle_remote_streaming/3` in `HttpHandler` / `Socks5Handler`.
  """
  @spec start_forwarding(:gen_tcp.socket(), :gen_tcp.socket(), map()) :: :ok
  def start_forwarding(client_socket, target_socket, metadata) do
    Forwarder.forward(client_socket, target_socket, metadata)
  end

  @doc """
  Returns the cluster name parsed from a VPN hostname, or nil if not a VPN target.
  """
  def cluster_name_from_hostname(target_host) do
    case parse_cluster_from_hostname(target_host) do
      {:ok, cluster_name} -> cluster_name
      {:error, _} -> nil
    end
  end

  # Direct VPN routing

  defp connect_direct(target_host, target_port, caller_pid, initial_data) do
    with {:ok, cluster_name} <- parse_cluster_from_hostname(target_host),
         {:ok, gateway_pid} <- lookup_gateway(cluster_name),
         {:ok, handle} <- gateway_connect(gateway_pid, target_host, target_port, caller_pid) do
      maybe_send_initial(handle, initial_data)
      {:ok, handle}
    end
  end

  defp parse_cluster_from_hostname(target_host) do
    domain = Application.get_env(:edge_admin, :netmaker_default_domain, "nm.internal")
    pattern = ~r/(cluster-[^.]+)\.#{Regex.escape(domain)}$/

    case Regex.run(pattern, target_host) do
      [_, cluster_name] ->
        {:ok, cluster_name}

      nil ->
        ErrorHandler.log_error(:invalid_target, %{target_host: target_host})
        {:error, :not_vpn_target}
    end
  end

  defp lookup_gateway(cluster_name) do
    case Gateway.lookup(cluster_name) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, :no_owner} = err ->
        ErrorHandler.log_error(:no_cluster_owner, %{cluster_name: cluster_name})
        err

      {:error, :gateway_not_found} = err ->
        ErrorHandler.log_error(:no_gateway, %{cluster_name: cluster_name})
        err
    end
  end

  defp gateway_connect(gateway_pid, target_host, target_port, caller_pid) do
    case Gateway.tcp_connect(gateway_pid, target_host, target_port, caller_pid) do
      {:ok, target_socket} ->
        {:ok, {:local, target_socket}}

      {:ok, :remote, proxy_pid} ->
        {:ok, {:remote, proxy_pid}}

      {:error, reason} = err ->
        ErrorHandler.log_error(reason, %{
          target_host: target_host,
          target_port: target_port,
          source: :gateway
        })

        err
    end
  end

  defp maybe_send_initial(_handle, nil), do: :ok

  defp maybe_send_initial({:local, socket}, data) do
    :gen_tcp.send(socket, data)
    :ok
  end

  defp maybe_send_initial({:remote, proxy_pid}, data) do
    send(proxy_pid, {:send_to_target, data})
    :ok
  end

  # Proxy chaining

  defp connect_via_agent_proxy(exit_node, target_host, target_port, caller_pid, initial_data, protocol) do
    node_dns = EdgeAdmin.Nodes.Schemas.Node.vpn_hostname(exit_node)
    agent_proxy_port = agent_proxy_port(protocol)

    with {:ok, cluster_name} <- parse_cluster_from_hostname(node_dns),
         {:ok, gateway_pid} <- lookup_gateway(cluster_name),
         {:ok, handle} <- gateway_connect(gateway_pid, node_dns, agent_proxy_port, caller_pid),
         :ok <- handshake(handle, protocol, target_host, target_port, exit_node.proxy_password, initial_data) do
      {:ok, handle}
    else
      {:error, _} = err -> err
    end
  end

  defp agent_proxy_port(:http), do: Application.get_env(:edge_agent, :http_proxy_port, 43_128)
  defp agent_proxy_port(:socks5), do: Application.get_env(:edge_agent, :socks5_proxy_port, 41_080)

  # Local handle handshake

  defp handshake({:local, socket}, :http, target_host, target_port, proxy_password, initial_data) do
    auth_header = "Proxy-Authorization: Basic #{Base.encode64("_:#{proxy_password}")}\r\n"

    request =
      "CONNECT #{target_host}:#{target_port} HTTP/1.1\r\n" <>
        "Host: #{target_host}:#{target_port}\r\n" <>
        auth_header <>
        "\r\n"

    with :ok <- :gen_tcp.send(socket, request),
         {:ok, _status, _rest} <- read_http_status_passive(socket) do
      if initial_data, do: :gen_tcp.send(socket, initial_data)
      :ok
    else
      {:error, reason} ->
        ErrorHandler.log_error(:proxy_rejected, %{protocol: :http, reason: reason})
        :gen_tcp.close(socket)
        {:error, :proxy_rejected}
    end
  end

  defp handshake({:local, socket}, :socks5, target_host, target_port, proxy_password, initial_data) do
    with {:ok, leftover1} <- socks5_negotiate_auth(socket),
         {:ok, leftover2} <- socks5_authenticate(socket, proxy_password, leftover1),
         :ok <- socks5_connect(socket, target_host, target_port, leftover2) do
      if initial_data, do: :gen_tcp.send(socket, initial_data)
      :ok
    else
      {:error, reason} ->
        ErrorHandler.log_error(:proxy_rejected, %{protocol: :socks5, reason: reason})
        :gen_tcp.close(socket)
        {:error, :proxy_rejected}
    end
  end

  # Remote handle handshake — delegated to the RemoteTunnel proxy on the peer node.
  defp handshake({:remote, proxy_pid}, protocol, target_host, target_port, proxy_password, initial_data) do
    handshake = build_proxy_handshake(protocol, target_host, target_port, proxy_password)
    send(proxy_pid, {:send_to_target, handshake})

    {consume_msg, reply_msg} =
      case protocol do
        :http -> {:consume_http_response, :http_response_consumed}
        :socks5 -> {:consume_socks5_response, :socks5_response_consumed}
      end

    send(proxy_pid, {consume_msg, self()})

    receive do
      {^reply_msg, ^proxy_pid, {:ok, :accepted}} ->
        if initial_data, do: send(proxy_pid, {:send_to_target, initial_data})
        :ok

      {^reply_msg, ^proxy_pid, {:error, reason}} ->
        ErrorHandler.log_error(:proxy_rejected, %{reason: reason, protocol: protocol, mode: :remote})
        send(proxy_pid, :close)
        {:error, :proxy_rejected}
    after
      Config.handshake_timeout() ->
        send(proxy_pid, :close)
        {:error, :timeout}
    end
  end

  defp parse_or_read(socket, parser, leftover) do
    case parser.(leftover) do
      {:ok, _, _} = ok ->
        ok

      {:error, _} = err ->
        err

      {:need_more, _} ->
        case :gen_tcp.recv(socket, 0, Config.handshake_timeout()) do
          {:ok, data} -> parse_or_read(socket, parser, leftover <> data)
          {:error, _} = err -> err
        end
    end
  end

  defp read_http_status_passive(socket) do
    parser = fn buf ->
      case :binary.split(buf, "\r\n\r\n") do
        [_headers, _rest] ->
          case parse_http_status_line(buf) do
            {:ok, status} when status >= 200 and status < 300 -> {:ok, status, <<>>}
            {:ok, status} -> {:error, {:http_status, status}}
            :error -> {:error, :bad_response}
          end

        [_] ->
          {:need_more, 0}
      end
    end

    BufferedReader.read_passive(socket, parser, Config.handshake_timeout())
  end

  defp parse_http_status_line(<<"HTTP/1.", _v, " ", code::binary-size(3), _rest::binary>>) do
    case Integer.parse(code) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_http_status_line(_), do: :error

  defp check_method(0), do: :ok
  defp check_method(2), do: :ok
  defp check_method(0xFF), do: {:error, :no_acceptable_methods}
  defp check_method(m), do: {:error, {:unsupported_method, m}}

  defp check_auth(0), do: :ok
  defp check_auth(_), do: {:error, :socks5_auth_failed}

  defp check_connect(0), do: :ok
  defp check_connect(code), do: {:error, {:socks5_connect, code}}

  defp socks5_negotiate_auth(socket) do
    with :ok <- :gen_tcp.send(socket, Socks5Codec.encode_greeting_userpass()),
         {:ok, method, leftover} <-
           BufferedReader.read_passive(socket, &Socks5Codec.parse_method_reply/1, Config.handshake_timeout()),
         :ok <- check_method(method) do
      {:ok, leftover}
    end
  end

  defp socks5_authenticate(socket, proxy_password, leftover) do
    with :ok <- :gen_tcp.send(socket, Socks5Codec.encode_auth_request("_", proxy_password)),
         {:ok, auth_status, rest} <- parse_or_read(socket, &Socks5Codec.parse_auth_response/1, leftover),
         :ok <- check_auth(auth_status) do
      {:ok, rest}
    end
  end

  defp socks5_connect(socket, target_host, target_port, leftover) do
    with :ok <- :gen_tcp.send(socket, Socks5Codec.encode_connect_request_domain(target_host, target_port)),
         {:ok, {rep, _bnd_host, _bnd_port}, _rest} <-
           parse_or_read(socket, &Socks5Codec.parse_reply/1, leftover) do
      check_connect(rep)
    end
  end

  defp build_proxy_handshake(:http, target_host, target_port, proxy_password) do
    auth_header = "Proxy-Authorization: Basic #{Base.encode64("_:#{proxy_password}")}\r\n"

    "CONNECT #{target_host}:#{target_port} HTTP/1.1\r\n" <>
      "Host: #{target_host}:#{target_port}\r\n" <>
      auth_header <>
      "\r\n"
  end

  defp build_proxy_handshake(:socks5, target_host, target_port, proxy_password) do
    IO.iodata_to_binary([
      Socks5Codec.encode_greeting_userpass(),
      Socks5Codec.encode_auth_request("_", proxy_password),
      Socks5Codec.encode_connect_request_domain(target_host, target_port)
    ])
  end
end
