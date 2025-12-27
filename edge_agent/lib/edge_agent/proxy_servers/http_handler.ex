# edge_agent/lib/edge_agent/proxy_server/http_handler.ex
defmodule EdgeAgent.ProxyServers.HttpHandler do
  @moduledoc """
  Ranch protocol handler for HTTP forward proxy.

  Supports:
  - CONNECT method for HTTPS/WebSocket (TCP tunneling)
  - Regular HTTP methods (GET, POST, etc.)

  Authentication via Proxy-Authorization header (Basic auth).
  """

  @behaviour :ranch_protocol

  alias EdgeAgent.ProxyServers.Authentication
  alias EdgeAgent.ProxyServers.Config
  alias EdgeAgent.ProxyServers.ErrorHandler
  alias EdgeAgent.ProxyServers.TcpTunnel

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

    start_time = System.monotonic_time(:millisecond)

    result =
      case handle_http_request(socket, transport) do
        :ok ->
          :ok

        {:error, reason} ->
          _error_category = ErrorHandler.log_error(reason, %{protocol: :http})
          transport.close(socket)
          {:error, reason}
      end

    duration = System.monotonic_time(:millisecond) - start_time

    # Emit connection telemetry
    {conn_result, telemetry_meta} =
      case result do
        :ok ->
          {:success, %{result: :success, protocol: :http}}
        {:error, :auth_failed} ->
          {:auth_failed, %{result: :auth_failed, protocol: :http}}
        {:error, reason} ->
          {:failure, ErrorHandler.telemetry_metadata(reason, :http) |> Map.put(:result, :failure)}
      end

    :telemetry.execute(
      [:edge_agent, :proxy, :http, :connection],
      %{count: 1, total: 1},
      telemetry_meta
    )

    # Emit session duration telemetry if connection was successful
    if conn_result == :success do
      :telemetry.execute(
        [:edge_agent, :proxy, :session, :duration],
        %{duration: duration},
        %{protocol: :http}
      )
    end

    result
  end

  defp handle_http_request(socket, transport) do
    case read_http_request(socket, transport) do
      {:ok, method, uri, http_version, headers, _body} ->
        # Check authentication
        case authenticate_request(headers) do
          :ok ->
            handle_authenticated_request(socket, transport, method, uri, http_version, headers)

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
    # Format: "Basic base64(username:password)"
    case String.split(auth_header, " ", parts: 2) do
      ["Basic", encoded] ->
        case Base.decode64(encoded) do
          {:ok, decoded} ->
            case String.split(decoded, ":", parts: 2) do
              [username, password] ->
                case Authentication.authenticate(username, password) do
                  :ok ->
                    Logger.info("HTTP proxy authentication successful for user: #{username}")
                    :ok

                  {:error, reason} = error ->
                    Logger.warning("HTTP proxy authentication failed for user: #{username}, reason: #{inspect(reason)}")
                    error
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

  defp handle_authenticated_request(socket, transport, method, uri, http_version, headers) do
    case method do
      "CONNECT" ->
        handle_connect_method(socket, transport, uri)

      _ ->
        handle_regular_http_method(socket, transport, method, uri, http_version, headers)
    end
  end

  defp handle_connect_method(socket, transport, uri) do
    # CONNECT host:port HTTP/1.1
    case parse_host_port(uri) do
      {:ok, host, port} ->
        Logger.info("HTTP CONNECT to #{host}:#{port}")

        case TcpTunnel.connect_and_forward(socket, host, port) do
          {:ok, _target_socket} ->
            send_connect_success(socket, transport)
            # Tunnel is now active, forwarding tasks are running
            # Keep the handler process alive
            :timer.sleep(:infinity)

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

  defp handle_regular_http_method(socket, transport, method, uri, http_version, headers) do
    # For regular HTTP (not CONNECT), parse the full URL
    # URI format: http://host:port/path
    case parse_http_uri(uri) do
      {:ok, host, port, path} ->
        Logger.info("HTTP #{method} to #{host}:#{port}#{path}")
        forward_http_request(socket, transport, method, host, port, path, http_version, headers)

      {:error, reason} ->
        {status, message} = ErrorHandler.http_error_response(reason)
        send_error(socket, transport, status, message)
        {:error, reason}
    end
  end

  defp parse_http_uri(uri) do
    # Parse http://host:port/path or http://host/path
    case URI.parse(uri) do
      %URI{scheme: scheme, host: host, port: port, path: path} when scheme in ["http", "https"] ->
        # Use default port if not specified
        port = port || (if scheme == "https", do: 443, else: 80)
        path = path || "/"
        {:ok, host, port, path}

      _ ->
        {:error, :invalid_uri}
    end
  end

  defp forward_http_request(socket, transport, method, host, port, path, http_version, headers) do
    # Build the HTTP request to send to target
    filtered_headers = Enum.reject(headers, fn {k, _v} ->
      String.downcase(k) in ["proxy-authorization", "proxy-connection"]
    end)

    request_line = "#{method} #{path} #{http_version}\r\n"
    header_lines = Enum.map(filtered_headers, fn {k, v} -> "#{k}: #{v}\r\n" end)
    request = IO.iodata_to_binary([request_line | header_lines] ++ ["\r\n"])

    # Establish tunnel and send HTTP request through it
    case TcpTunnel.connect_and_forward(socket, host, port, request) do
      {:ok, _target_socket} ->
        # Socket forwarding already set up with request sent, keep alive
        :timer.sleep(:infinity)

      {:error, reason} ->
        {status, message} = ErrorHandler.http_error_response(reason)
        send_error(socket, transport, status, message)
        {:error, reason}
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
      {:ok, data} ->
        parse_http_request(data)

      {:error, reason} ->
        {:error, reason}
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
    Enum.reduce(lines, [], fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          [{String.trim(key) |> String.downcase(), String.trim(value)} | acc]

        _ ->
          acc
      end
    end)
    |> Enum.reverse()
  end

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
        "Proxy-Authenticate: Basic realm=\"Edge Agent Proxy\"\r\n\r\n"

    transport.send(socket, response)
  end
end
