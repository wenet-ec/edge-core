# edge_admin/lib/edge_admin/proxy_servers/http_handler.ex
defmodule EdgeAdmin.ProxyServers.HttpHandler do
  @moduledoc """
  Ranch protocol handler for HTTP forward proxy.

  Supports:
  - CONNECT method for HTTPS/WebSocket (TCP tunneling)
  - Regular HTTP methods (GET, POST, etc.)

  Authentication via Proxy-Authorization header (Basic auth).
  Routes through Gateway using cluster name from target hostname.
  """

  @behaviour :ranch_protocol

  alias EdgeAdmin.ProxyServers.Authentication
  alias EdgeAdmin.ProxyServers.Config
  alias EdgeAdmin.ProxyServers.ErrorHandler
  alias EdgeAdmin.ProxyServers.TcpTunnel

  require Logger

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

    case result do
      {:ok, routing_mode, proxy_mode, cluster_name} ->
        :telemetry.execute(
          [:edge_admin, :proxy, :connection],
          %{count: 1, total: 1},
          %{
            protocol: :http,
            result: :success,
            routing_mode: routing_mode,
            proxy_mode: proxy_mode,
            cluster: cluster_name
          }
        )

        :telemetry.execute(
          [:edge_admin, :proxy, :session, :duration],
          %{duration: duration_ms},
          %{protocol: :http, routing_mode: routing_mode, proxy_mode: proxy_mode, cluster: cluster_name}
        )

        :ok

      {:error, :auth_failed} ->
        :telemetry.execute(
          [:edge_admin, :proxy, :auth_failure],
          %{count: 1, total: 1},
          %{protocol: :http}
        )

        :telemetry.execute(
          [:edge_admin, :proxy, :connection],
          %{count: 1, total: 1},
          %{protocol: :http, result: :auth_failed, routing_mode: :unknown, proxy_mode: :unknown, cluster: "unknown"}
        )

        transport.close(socket)

      {:error, reason} ->
        _error_category = ErrorHandler.log_error(reason, %{protocol: :http})

        :telemetry.execute(
          [:edge_admin, :proxy, :connection],
          %{count: 1, total: 1},
          reason
          |> ErrorHandler.telemetry_metadata(:http)
          |> Map.merge(%{result: :failure, routing_mode: :unknown, proxy_mode: :unknown, cluster: "unknown"})
        )

        transport.close(socket)
    end
  end

  # Returns {:ok, routing_mode, proxy_mode, cluster_name} | {:error, reason}
  defp handle_http_request(socket, transport) do
    case read_http_request(socket, transport) do
      {:ok, method, uri, http_version, headers, _body} ->
        case authenticate_request(headers) do
          {:ok, routing_mode, exit_node} ->
            handle_authenticated_request(
              socket,
              transport,
              method,
              uri,
              http_version,
              headers,
              routing_mode,
              exit_node
            )

          {:error, _reason} ->
            send_auth_required(socket, transport)
            {:error, :auth_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp authenticate_request(headers) do
    case get_header(headers, "proxy-authorization") do
      nil ->
        {:error, :no_auth_header}

      auth_header ->
        parse_and_validate_auth(auth_header)
    end
  end

  defp parse_and_validate_auth(auth_header) do
    case String.split(auth_header, " ", parts: 2) do
      ["Basic", encoded] ->
        case Base.decode64(encoded) do
          {:ok, decoded} ->
            case String.split(decoded, ":", parts: 2) do
              [username, password] ->
                case Authentication.authenticate_and_parse(username, password) do
                  {:ok, :direct} -> {:ok, :direct, nil}
                  {:ok, :chain, node} -> {:ok, :chain, node}
                  {:error, reason} -> {:error, reason}
                end

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

  defp handle_authenticated_request(socket, transport, method, uri, http_version, headers, routing_mode, exit_node) do
    case method do
      "CONNECT" ->
        handle_connect_method(socket, transport, uri, routing_mode, exit_node)

      _ ->
        handle_regular_http_method(
          socket,
          transport,
          method,
          uri,
          http_version,
          headers,
          routing_mode,
          exit_node
        )
    end
  end

  defp handle_connect_method(socket, transport, uri, routing_mode, exit_node) do
    case parse_host_port(uri) do
      {:ok, host, port} ->
        opts = build_tunnel_opts(routing_mode, exit_node, :http)
        proxy_mode = if routing_mode == :chain, do: :chain, else: :direct
        cluster_name = TcpTunnel.cluster_name_from_hostname(host) || "unknown"

        case TcpTunnel.connect_and_forward(socket, host, port, self(), nil, opts) do
          {:ok, :local, _target_socket} ->
            send_connect_success(socket, transport)
            :timer.sleep(:infinity)
            {:ok, :local, proxy_mode, cluster_name}

          {:ok, :remote, proxy_pid} ->
            send_connect_success(socket, transport)
            transport.setopts(socket, active: true)
            handle_remote_streaming(socket, transport, proxy_pid)
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
    # Build HTTP request to send to target
    filtered_headers = filter_proxy_headers(headers)
    request = build_http_request(method, path, http_version, filtered_headers)

    # Determine if this is a VPN target
    domain = Application.get_env(:edge_admin, :netmaker_default_domain, "nm.internal")
    is_vpn_target = String.ends_with?(host, ".#{domain}")

    # Route accordingly
    if routing_mode == :chain or is_vpn_target do
      # Use TcpTunnel for VPN targets or proxy chaining
      opts = build_tunnel_opts(routing_mode, exit_node, :http)
      proxy_mode = if routing_mode == :chain, do: :chain, else: :direct
      tunnel_http_request(socket, transport, host, port, request, opts, proxy_mode)
    else
      # Direct connection for non-VPN targets
      direct_http_request(socket, transport, host, port, request)
    end
  end

  defp tunnel_http_request(socket, transport, host, port, request, opts, proxy_mode) do
    cluster_name = TcpTunnel.cluster_name_from_hostname(host) || "unknown"

    case TcpTunnel.connect_and_forward(socket, host, port, self(), request, opts) do
      {:ok, :local, _target_socket} ->
        :timer.sleep(:infinity)
        {:ok, :local, proxy_mode, cluster_name}

      {:ok, :remote, proxy_pid} ->
        transport.setopts(socket, active: true)
        handle_remote_streaming(socket, transport, proxy_pid)
        {:ok, :remote, proxy_mode, cluster_name}

      {:error, reason} ->
        {status, message} = ErrorHandler.http_error_response(reason)
        send_error(socket, transport, status, message)
        {:error, reason}
    end
  end

  defp direct_http_request(socket, transport, host, port, request) do
    case :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false], Config.connection_timeout()) do
      {:ok, target_socket} ->
        :gen_tcp.send(target_socket, request)
        setup_bidirectional_forwarding(socket, target_socket)
        :timer.sleep(:infinity)
        {:ok, :local, :direct, "external"}

      {:error, reason} ->
        {status, message} = ErrorHandler.http_error_response(reason)
        send_error(socket, transport, status, message)
        {:error, reason}
    end
  end

  defp setup_bidirectional_forwarding(client_socket, target_socket) do
    forwarder_pid = spawn_link(fn -> forward_loop(client_socket, target_socket) end)
    :gen_tcp.controlling_process(client_socket, forwarder_pid)
    spawn_link(fn -> forward_loop(target_socket, client_socket) end)
  end

  defp forward_loop(source_socket, dest_socket) do
    case :gen_tcp.recv(source_socket, 0, Config.recv_timeout()) do
      {:ok, data} ->
        :gen_tcp.send(dest_socket, data)
        forward_loop(source_socket, dest_socket)

      {:error, _reason} ->
        :gen_tcp.close(source_socket)
        :gen_tcp.close(dest_socket)
    end
  end

  # Handle remote streaming (message-based via RemoteTunnel proxy)
  defp handle_remote_streaming(socket, transport, proxy_pid) do
    receive do
      {:tcp, ^socket, data} ->
        send(proxy_pid, {:send_to_target, data})
        handle_remote_streaming(socket, transport, proxy_pid)

      {:remote_target_data, ^proxy_pid, data} ->
        transport.send(socket, data)
        handle_remote_streaming(socket, transport, proxy_pid)

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
    end
  end

  # Helper functions

  defp build_tunnel_opts(:direct, _exit_node, _protocol), do: []
  defp build_tunnel_opts(:chain, exit_node, protocol), do: [exit_node: exit_node, protocol: protocol]

  defp filter_proxy_headers(headers) do
    Enum.reject(headers, fn {k, _v} ->
      String.downcase(k) in ["proxy-authorization", "proxy-connection"]
    end)
  end

  defp build_http_request(method, path, http_version, headers) do
    request_line = "#{method} #{path} #{http_version}\r\n"
    header_lines = Enum.map(headers, fn {k, v} -> "#{k}: #{v}\r\n" end)
    IO.iodata_to_binary([request_line | header_lines] ++ ["\r\n"])
  end

  defp parse_http_uri(uri) do
    case URI.parse(uri) do
      %URI{scheme: scheme, host: host, port: port, path: path} when scheme in ["http", "https"] ->
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

  defp read_http_request(socket, transport) do
    case read_until_double_crlf(socket, transport, <<>>) do
      {:ok, data} -> parse_http_request(data)
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_until_double_crlf(socket, transport, buffer) do
    case transport.recv(socket, 0, Config.read_timeout()) do
      {:ok, data} ->
        new_buffer = buffer <> data

        if String.contains?(new_buffer, "\r\n\r\n") do
          {:ok, new_buffer}
        else
          read_until_double_crlf(socket, transport, new_buffer)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_http_request(data) do
    case String.split(data, "\r\n\r\n", parts: 2) do
      [headers_part, body] ->
        parse_headers_part(headers_part, body)

      [headers_part] ->
        parse_headers_part(headers_part, "")
    end
  end

  defp parse_headers_part(headers_part, body) do
    lines = String.split(headers_part, "\r\n")

    case lines do
      [request_line | header_lines] ->
        case parse_request_line(request_line) do
          {:ok, method, uri, version} ->
            headers = parse_headers(header_lines)
            {:ok, method, uri, version, headers, body}

          error ->
            error
        end

      _ ->
        {:error, :invalid_request}
    end
  end

  defp parse_request_line(line) do
    case String.split(line, " ", parts: 3) do
      [method, uri, version] -> {:ok, method, uri, version}
      _ -> {:error, :invalid_request_line}
    end
  end

  defp parse_headers(lines) do
    lines
    |> Enum.reduce([], fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          [{key |> String.trim() |> String.downcase(), String.trim(value)} | acc]

        _ ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  @dialyzer {:nowarn_function, get_header: 2}
  defp get_header(headers, key) do
    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(k) == String.downcase(key), do: v
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
