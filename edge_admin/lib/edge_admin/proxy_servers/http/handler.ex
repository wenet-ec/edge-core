# edge_admin/lib/edge_admin/proxy_servers/http/handler.ex
defmodule EdgeAdmin.ProxyServers.Http.Handler do
  @moduledoc """
  Ranch protocol handler for HTTP forward proxy.

  Supports:
  - CONNECT method for HTTPS/WebSocket (TCP tunneling)
  - Regular HTTP methods (GET, POST, etc.) — one request per connection

  Authentication via Proxy-Authorization header (Basic auth).
  Routes through Gateway using cluster name from target hostname.
  """

  @behaviour :ranch_protocol

  alias EdgeAdmin.ProxyServers.Authentication
  alias EdgeAdmin.ProxyServers.Config
  alias EdgeAdmin.ProxyServers.ErrorHandler
  alias EdgeAdmin.ProxyServers.Http.Parser, as: HttpParser
  alias EdgeAdmin.ProxyServers.Transport.Forwarder
  alias EdgeAdmin.ProxyServers.Transport.TunnelRegistry
  alias EdgeAdmin.ProxyServers.Tunnel.TcpTunnel

  require Logger

  @hop_by_hop_headers ~w(
    connection
    keep-alive
    proxy-authenticate
    proxy-authorization
    proxy-connection
    te
    trailer
    transfer-encoding
    upgrade
  )

  @impl true
  def start_link(ref, transport, opts) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [ref, transport, opts])
    {:ok, pid}
  end

  def init(ref, transport, _opts) do
    {:ok, socket} = :ranch.handshake(ref)
    {:ok, {client_ip, client_port}} = :inet.peername(socket)
    Logger.info("HTTP proxy client connected from #{:inet.ntoa(client_ip)}:#{client_port}")

    start_time = System.monotonic_time()
    result = handle_http_request(socket, transport)
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
      %{protocol: :http, result: :success, routing_mode: routing_mode, proxy_mode: proxy_mode, cluster: cluster_name}
    )

    :telemetry.execute(
      [:edge_admin, :proxy, :session, :duration],
      %{duration: duration_ms},
      %{protocol: :http, routing_mode: routing_mode, proxy_mode: proxy_mode, cluster: cluster_name}
    )
  end

  defp emit_telemetry({:error, :auth_failed}, _duration_ms) do
    :telemetry.execute([:edge_admin, :proxy, :auth_failure], %{count: 1, total: 1}, %{protocol: :http})

    :telemetry.execute(
      [:edge_admin, :proxy, :connection],
      %{count: 1, total: 1},
      %{protocol: :http, result: :auth_failed, routing_mode: :unknown, proxy_mode: :unknown, cluster: "unknown"}
    )
  end

  defp emit_telemetry({:error, reason}, _duration_ms) do
    _ = ErrorHandler.log_error(reason, %{protocol: :http})

    :telemetry.execute(
      [:edge_admin, :proxy, :connection],
      %{count: 1, total: 1},
      reason
      |> ErrorHandler.telemetry_metadata(:http)
      |> Map.merge(%{result: :failure, routing_mode: :unknown, proxy_mode: :unknown, cluster: "unknown"})
    )
  end

  defp handle_http_request(socket, transport) do
    case HttpParser.read_request(socket, transport, Config.read_timeout()) do
      {:ok, %{method: method, uri: uri, version: version, headers: headers}, _body} ->
        with :ok <- validate_proxy_form(method, uri),
             :ok <- check_loop(headers),
             {:ok, routing_mode, exit_node} <- authenticate_request(socket, transport, headers) do
          dispatch_method(socket, transport, method, uri, version, headers, routing_mode, exit_node)
        else
          {:error, :auth_failed} = err ->
            err

          {:error, reason} ->
            {status, message} = ErrorHandler.http_error_response(reason)
            send_error(socket, transport, status, message)
            {:error, reason}
        end

      {:error, reason} ->
        {status, message} = ErrorHandler.http_error_response(reason)
        send_error(socket, transport, status, message)
        {:error, reason}
    end
  end

  defp validate_proxy_form("CONNECT", _uri), do: :ok

  defp validate_proxy_form(_method, uri) do
    case URI.parse(uri) do
      %URI{scheme: s, host: h} when is_binary(s) and is_binary(h) -> :ok
      _ -> {:error, :origin_form_uri}
    end
  end

  defp check_loop(headers) do
    pseudonym = via_pseudonym()

    case get_header(headers, "via") do
      nil ->
        :ok

      via ->
        if String.contains?(via, pseudonym) do
          {:error, :loop_detected}
        else
          :ok
        end
    end
  end

  defp authenticate_request(socket, transport, headers) do
    case get_header(headers, "proxy-authorization") do
      nil ->
        send_auth_required(socket, transport)
        {:error, :auth_failed}

      auth_header ->
        case parse_and_validate_auth(auth_header) do
          {:ok, :direct} ->
            {:ok, :direct, nil}

          {:ok, :chain, node} ->
            {:ok, :chain, node}

          {:error, _reason} ->
            send_auth_required(socket, transport)
            {:error, :auth_failed}
        end
    end
  end

  defp parse_and_validate_auth(auth_header) do
    case String.split(auth_header, " ", parts: 2) do
      ["Basic", encoded] ->
        case Base.decode64(encoded) do
          {:ok, decoded} ->
            case String.split(decoded, ":", parts: 2) do
              [username, password] ->
                Authentication.authenticate_and_parse(username, password)

              _ ->
                {:error, :invalid_format}
            end

          :error ->
            {:error, :invalid_base64}
        end

      _ ->
        {:error, :invalid_auth_type}
    end
  end

  defp dispatch_method(socket, transport, "CONNECT", uri, _version, _headers, routing_mode, exit_node) do
    handle_connect_method(socket, transport, uri, routing_mode, exit_node)
  end

  defp dispatch_method(socket, transport, method, uri, version, headers, routing_mode, exit_node) do
    handle_regular_http_method(socket, transport, method, uri, version, headers, routing_mode, exit_node)
  end

  defp handle_connect_method(socket, transport, uri, routing_mode, exit_node) do
    case parse_host_port(uri) do
      {:ok, host, port} ->
        opts = tunnel_opts(routing_mode, exit_node)
        proxy_mode = if routing_mode == :chain, do: :chain, else: :direct
        cluster_name = TcpTunnel.cluster_name_from_hostname(host) || "unknown"
        metadata = forward_metadata(host, port, :connect, routing_mode, cluster_name)

        case TcpTunnel.connect(host, port, self(), opts) do
          {:ok, {:local, target_socket}} ->
            send_connect_success(socket, transport)
            :ok = TunnelRegistry.register(metadata)

            try do
              TcpTunnel.start_forwarding(socket, target_socket, metadata)
            after
              TunnelRegistry.unregister()
            end

            {:ok, :local, proxy_mode, cluster_name}

          {:ok, {:remote, proxy_pid}} ->
            send_connect_success(socket, transport)
            transport.setopts(socket, active: true)
            :ok = TunnelRegistry.register(metadata)

            try do
              handle_remote_streaming(socket, transport, proxy_pid)
            after
              TunnelRegistry.unregister()
            end

            {:ok, :remote, proxy_mode, cluster_name}

          {:error, reason} ->
            {status, message} = ErrorHandler.http_error_response(reason)
            send_error(socket, transport, status, message)
            {:error, reason}
        end

      {:error, reason} ->
        {status, message} = ErrorHandler.http_error_response(reason)
        send_error(socket, transport, status, message)
        {:error, reason}
    end
  end

  defp handle_regular_http_method(socket, transport, method, uri, http_version, headers, routing_mode, exit_node) do
    case parse_http_uri(uri) do
      {:ok, host, port, path} ->
        forward_http_request(
          socket,
          transport,
          method,
          host,
          port,
          path,
          http_version,
          headers,
          routing_mode,
          exit_node
        )

      {:error, reason} ->
        {status, message} = ErrorHandler.http_error_response(reason)
        send_error(socket, transport, status, message)
        {:error, reason}
    end
  end

  defp forward_http_request(socket, transport, method, host, port, path, http_version, headers, routing_mode, exit_node) do
    is_vpn_target = vpn_target?(host)

    headers_to_send =
      headers
      |> reconcile_host_header(host, port)
      |> filter_hop_by_hop_headers()
      |> add_via_header(http_version)

    request = build_http_request(method, path, http_version, headers_to_send)

    if routing_mode == :chain or is_vpn_target do
      opts = tunnel_opts(routing_mode, exit_node)
      opts = Keyword.put(opts, :initial_data, request)
      cluster_name = TcpTunnel.cluster_name_from_hostname(host) || "unknown"
      metadata = forward_metadata(host, port, :request, routing_mode, cluster_name)
      proxy_mode = if routing_mode == :chain, do: :chain, else: :direct

      tunnel_http_request(socket, transport, host, port, opts, metadata, proxy_mode, cluster_name)
    else
      direct_http_request(socket, transport, host, port, request)
    end
  end

  defp vpn_target?(host) do
    domain = Application.get_env(:edge_admin, :netmaker_default_domain, "nm.internal")
    String.ends_with?(host, ".#{domain}")
  end

  defp tunnel_http_request(socket, transport, host, port, opts, metadata, proxy_mode, cluster_name) do
    case TcpTunnel.connect(host, port, self(), opts) do
      {:ok, {:local, target_socket}} ->
        :ok = TunnelRegistry.register(metadata)

        try do
          TcpTunnel.start_forwarding(socket, target_socket, metadata)
        after
          TunnelRegistry.unregister()
        end

        {:ok, :local, proxy_mode, cluster_name}

      {:ok, {:remote, proxy_pid}} ->
        transport.setopts(socket, active: true)
        :ok = TunnelRegistry.register(metadata)

        try do
          handle_remote_streaming(socket, transport, proxy_pid)
        after
          TunnelRegistry.unregister()
        end

        {:ok, :remote, proxy_mode, cluster_name}

      {:error, reason} ->
        {status, message} = ErrorHandler.http_error_response(reason)
        send_error(socket, transport, status, message)
        {:error, reason}
    end
  end

  defp direct_http_request(socket, transport, host, port, request) do
    metadata = %{target: :external, host: host, port: port, protocol: :http}

    with :ok <- validate_external_destination(host, port),
         {:ok, target_socket} <-
           :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false], Config.connection_timeout()) do
      :gen_tcp.send(target_socket, request)
      :ok = TunnelRegistry.register(metadata)

      try do
        Forwarder.forward(socket, target_socket, metadata)
      after
        TunnelRegistry.unregister()
      end

      {:ok, :local, :direct, "external"}
    else
      {:error, reason} ->
        {status, message} = ErrorHandler.http_error_response(reason)
        send_error(socket, transport, status, message)
        {:error, reason}
    end
  end

  # Remote streaming loop (message-based via RemoteTunnel proxy on peer node)
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
        :ok

      {:remote_target_error, ^proxy_pid, _reason} ->
        transport.close(socket)
        :ok

      {:tcp_closed, ^socket} ->
        send(proxy_pid, :close)
        :ok

      {:tcp_error, ^socket, _reason} ->
        send(proxy_pid, :close)
        :ok

      {:drain, grace_ms} ->
        handle_remote_streaming(socket, transport, proxy_pid, min(timeout, grace_ms))
    after
      timeout ->
        send(proxy_pid, :close)
        transport.close(socket)
        :ok
    end
  end

  # Helpers

  defp tunnel_opts(:direct, _exit_node), do: []
  defp tunnel_opts(:chain, exit_node), do: [exit_node: exit_node, protocol: :http]

  defp forward_metadata(host, port, kind, routing_mode, cluster_name) do
    %{
      protocol: :http,
      target_host: host,
      target_port: port,
      kind: kind,
      routing_mode: routing_mode,
      cluster: cluster_name
    }
  end

  defp reconcile_host_header(headers, host, port) do
    host_value =
      case port do
        80 -> host
        443 -> host
        _ -> "#{host}:#{port}"
      end

    [{"host", host_value} | Enum.reject(headers, fn {k, _} -> String.downcase(k) == "host" end)]
  end

  defp filter_hop_by_hop_headers(headers) do
    connection_listed =
      headers
      |> get_header("connection")
      |> to_string()
      |> String.split(",", trim: true)
      |> Enum.map(&(&1 |> String.trim() |> String.downcase()))

    drop = MapSet.new(@hop_by_hop_headers ++ connection_listed)
    has_upgrade = "upgrade" in connection_listed

    filtered = Enum.reject(headers, fn {k, _v} -> String.downcase(k) in drop end)

    if has_upgrade do
      preserve_upgrade(headers, filtered)
    else
      filtered
    end
  end

  defp preserve_upgrade(original_headers, filtered) do
    upgrade = get_header(original_headers, "upgrade")
    with_connection = [{"connection", "Upgrade"} | filtered]

    if upgrade do
      [{"upgrade", upgrade} | with_connection]
    else
      with_connection
    end
  end

  defp add_via_header(headers, http_version) do
    version = parse_http_version(http_version)
    pseudonym = via_pseudonym()
    new_entry = "#{version} #{pseudonym}"

    updated =
      case get_header(headers, "via") do
        nil -> new_entry
        existing -> "#{existing}, #{new_entry}"
      end

    [{"via", updated} | Enum.reject(headers, fn {k, _} -> String.downcase(k) == "via" end)]
  end

  defp parse_http_version("HTTP/1.0"), do: "1.0"
  defp parse_http_version("HTTP/1.1"), do: "1.1"
  defp parse_http_version("HTTP/" <> rest), do: rest
  defp parse_http_version(_), do: "1.1"

  defp via_pseudonym do
    Application.get_env(:edge_admin, :via_pseudonym, "edge-admin")
  end

  defp validate_external_destination(host, port) do
    cond do
      loopback?(host) -> {:error, :localhost_blocked}
      link_local?(host) -> {:error, :link_local_blocked}
      metadata_service?(host) -> {:error, :metadata_service_blocked}
      port in blocked_ports() -> {:error, :blocked_port}
      true -> :ok
    end
  end

  defp loopback?(host) do
    String.downcase(host) in ["localhost", "127.0.0.1", "0.0.0.0", "::1"] or
      String.starts_with?(host, "127.")
  end

  defp link_local?(host) do
    case parse_ipv4(host) do
      {169, 254, _, _} -> true
      _ -> false
    end
  end

  defp metadata_service?(host) do
    host_lower = String.downcase(host)

    host_lower in [
      "metadata.google.internal",
      "metadata.azure.com",
      "169.254.169.254",
      "100.100.100.200"
    ]
  end

  defp blocked_ports do
    [2375, 2376, 2377, 6443, 10_250, 10_255, 2379, 2380]
  end

  defp parse_ipv4(host) do
    case String.split(host, ".") do
      [a, b, c, d] ->
        with {a, ""} <- Integer.parse(a),
             {b, ""} <- Integer.parse(b),
             {c, ""} <- Integer.parse(c),
             {d, ""} <- Integer.parse(d) do
          {a, b, c, d}
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp build_http_request(method, path, http_version, headers) do
    request_line = "#{method} #{path} #{http_version}\r\n"
    header_lines = Enum.map(headers, fn {k, v} -> "#{k}: #{v}\r\n" end)
    IO.iodata_to_binary([request_line | header_lines] ++ ["\r\n"])
  end

  defp parse_http_uri(uri) do
    case URI.parse(uri) do
      %URI{scheme: scheme, host: host, port: port, path: path} when scheme in ["http", "https"] and is_binary(host) ->
        port = port || if scheme == "https", do: 443, else: 80
        path = path || "/"
        {:ok, host, port, path}

      _ ->
        {:error, :invalid_uri}
    end
  end

  defp parse_host_port(uri) do
    case String.split(uri, ":", parts: 2) do
      [host, port_str] ->
        case Integer.parse(port_str) do
          {port, _} -> {:ok, host, port}
          :error -> {:error, :invalid_port}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  defp get_header(headers, key) do
    key_down = String.downcase(key)

    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(k) == key_down, do: v
    end)
  end

  defp send_connect_success(socket, transport) do
    response = "HTTP/1.1 200 Connection established\r\n\r\n"
    transport.send(socket, response)
  end

  defp send_error(socket, transport, code, message) do
    response = "HTTP/1.1 #{code} #{message}\r\n\r\n"
    transport.send(socket, response)
  end

  defp send_auth_required(socket, transport) do
    response =
      "HTTP/1.1 407 Proxy Authentication Required\r\n" <>
        "Proxy-Authenticate: Basic realm=\"Edge Admin Proxy\"\r\n\r\n"

    transport.send(socket, response)
  end
end
