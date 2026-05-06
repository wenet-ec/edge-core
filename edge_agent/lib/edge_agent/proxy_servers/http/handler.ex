# edge_agent/lib/edge_agent/proxy_servers/http/handler.ex
defmodule EdgeAgent.ProxyServers.Http.Handler do
  @moduledoc """
  Ranch protocol handler for agent HTTP forward proxy.

  Supports:
  - CONNECT method for HTTPS/WebSocket (TCP tunneling)
  - Regular HTTP methods (GET, POST, etc.) — one request per connection.
    Origin must be `http://` (or rare cases where the proxy's plaintext
    upstream is acceptable). HTTPS origin URLs without CONNECT are
    structurally unsupported — TLS would need to terminate somewhere and
    the proxy doesn't decrypt.

  Authentication via Proxy-Authorization header (Basic auth).

  ## Known limitation: request bodies in non-CONNECT mode

  The parser returns any bytes that arrived after the `\\r\\n\\r\\n` header
  terminator as a `body_rest` value, but the handler currently discards it
  and forwards from the socket from scratch. If a client sends headers and
  body in the same TCP segment(s) (common for small bodies and on
  loopback), those body bytes are lost between header parse and
  `:gen_tcp.connect`. CONNECT mode is unaffected (no body in CONNECT).
  """

  @behaviour :ranch_protocol

  alias EdgeAgent.ProxyServers.Authentication
  alias EdgeAgent.ProxyServers.Config
  alias EdgeAgent.ProxyServers.ErrorHandler
  alias EdgeAgent.ProxyServers.Http.Parser, as: HttpParser
  alias EdgeAgent.ProxyServers.Transport.DestinationValidator
  alias EdgeAgent.ProxyServers.Transport.Forwarder
  alias EdgeAgent.ProxyServers.Transport.TunnelRegistry

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

    start_time = System.monotonic_time(:millisecond)

    result =
      case handle_http_request(socket, transport) do
        :ok ->
          :ok

        {:error, reason} ->
          _ = ErrorHandler.log_error(reason, %{protocol: :http})
          transport.close(socket)
          {:error, reason}
      end

    duration = System.monotonic_time(:millisecond) - start_time

    {conn_result, telemetry_meta} =
      case result do
        :ok ->
          {:success, %{result: :success, protocol: :http}}

        {:error, :auth_failed} ->
          {:auth_failed, %{result: :auth_failed, protocol: :http}}

        {:error, reason} ->
          {:failure, reason |> ErrorHandler.telemetry_metadata(:http) |> Map.put(:result, :failure)}
      end

    :telemetry.execute(
      [:edge_agent, :proxy, :http, :connection],
      %{count: 1, total: 1},
      telemetry_meta
    )

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
    case HttpParser.read_request(socket, transport, Config.read_timeout()) do
      {:ok, %{method: method, uri: uri, version: version, headers: headers}, _body} ->
        with :ok <- validate_proxy_form(method, uri),
             :ok <- check_loop(headers),
             :ok <- authenticate_request(socket, transport, headers) do
          dispatch_method(socket, transport, method, uri, version, headers)
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
          :ok ->
            :ok

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
              [username, password] -> Authentication.authenticate(username, password)
              _ -> {:error, :invalid_format}
            end

          :error ->
            {:error, :invalid_base64}
        end

      _ ->
        {:error, :invalid_auth_type}
    end
  end

  defp dispatch_method(socket, transport, "CONNECT", uri, _version, _headers) do
    handle_connect_method(socket, transport, uri)
  end

  defp dispatch_method(socket, transport, method, uri, version, headers) do
    handle_regular_http_method(socket, transport, method, uri, version, headers)
  end

  defp handle_connect_method(socket, transport, uri) do
    with {:ok, host, port} <- parse_host_port(uri),
         {:ok, ip_tuple} <- resolve_and_validate(host, port, "CONNECT") do
      metadata = %{protocol: :http, target_host: host, target_port: port, kind: :connect}

      case :gen_tcp.connect(ip_tuple, port, [:binary, packet: :raw, active: false], Config.connection_timeout()) do
        {:ok, target_socket} ->
          send_connect_success(socket, transport)
          :ok = TunnelRegistry.register(metadata)

          try do
            Forwarder.forward(socket, target_socket, metadata)
          after
            TunnelRegistry.unregister()
          end

        {:error, reason} ->
          {status, message} = ErrorHandler.http_error_response(reason)
          send_error(socket, transport, status, message)
          {:error, reason}
      end
    else
      {:error, reason} ->
        {status, message} = ErrorHandler.http_error_response(reason)
        send_error(socket, transport, status, message)
        {:error, reason}
    end
  end

  defp handle_regular_http_method(socket, transport, method, uri, http_version, headers) do
    with {:ok, host, port, path} <- parse_http_uri(uri),
         {:ok, ip_tuple} <- resolve_and_validate(host, port, method) do
      headers_to_send =
        headers
        |> reconcile_host_header(host, port)
        |> filter_hop_by_hop_headers()
        |> add_via_header(http_version)

      request = build_http_request(method, path, http_version, headers_to_send)
      metadata = %{protocol: :http, target_host: host, target_port: port, kind: :request, method: method}

      case :gen_tcp.connect(ip_tuple, port, [:binary, packet: :raw, active: false], Config.connection_timeout()) do
        {:ok, target_socket} ->
          :gen_tcp.send(target_socket, request)
          :ok = TunnelRegistry.register(metadata)

          try do
            Forwarder.forward(socket, target_socket, metadata)
          after
            TunnelRegistry.unregister()
          end

        {:error, reason} ->
          {status, message} = ErrorHandler.http_error_response(reason)
          send_error(socket, transport, status, message)
          {:error, reason}
      end
    else
      {:error, reason} ->
        {status, message} = ErrorHandler.http_error_response(reason)
        send_error(socket, transport, status, message)
        {:error, reason}
    end
  end

  defp resolve_and_validate(host, port, method) do
    case DestinationValidator.resolve_and_validate(host, port) do
      {:ok, ip} ->
        {:ok, ip}

      {:error, reason} ->
        :telemetry.execute(
          [:edge_agent, :proxy, :http, :blocked],
          %{count: 1},
          %{reason: reason, host: host, port: port, method: method}
        )

        {:error, reason}
    end
  end

  # Helpers

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
    Application.get_env(:edge_agent, :via_pseudonym, "edge-agent")
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
    transport.send(socket, "HTTP/1.1 200 Connection established\r\n\r\n")
  end

  defp send_error(socket, transport, code, message) do
    transport.send(socket, "HTTP/1.1 #{code} #{message}\r\n\r\n")
  end

  defp send_auth_required(socket, transport) do
    response =
      "HTTP/1.1 407 Proxy Authentication Required\r\n" <>
        "Proxy-Authenticate: Basic realm=\"Edge Agent Proxy\"\r\n\r\n"

    transport.send(socket, response)
  end
end
