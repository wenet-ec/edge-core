# edge_admin/lib/edge_admin/proxy_servers/http/parser.ex
defmodule EdgeAdmin.ProxyServers.Http.Parser do
  @moduledoc """
  HTTP/1.x request parser built on `:erlang.decode_packet/3`.

  Handles:
    * CRLF and LF line endings (native to `decode_packet`)
    * Header line folding (obsolete but still seen)
    * Case-insensitive header names (we lowercase on parse)
    * Max header size limit (default 64 KiB) to defend against slowloris

  Returns `{:ok, request_map, body_rest}` where `request_map` has:
    * `:method` (string, upper case for standard methods)
    * `:uri`    (request target as the client sent it — absolute form / authority form / origin form)
    * `:version` (e.g. `"HTTP/1.1"`)
    * `:headers` ([{lowercased_name, value}])
  """

  @max_header_bytes 64 * 1024

  @type request :: %{
          method: String.t(),
          uri: String.t(),
          version: String.t(),
          headers: [{String.t(), String.t()}]
        }

  @spec read_request(:gen_tcp.socket(), module(), timeout()) ::
          {:ok, request(), binary()} | {:error, term()}
  def read_request(socket, transport, timeout) do
    case read_request_line(socket, transport, <<>>, timeout) do
      {:ok, method, uri, version, rest} ->
        case read_headers(socket, transport, rest, [], byte_size(rest), timeout) do
          {:ok, headers, body_rest} ->
            {:ok, %{method: method, uri: uri, version: version, headers: headers}, body_rest}

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  defp read_request_line(socket, transport, buf, timeout) do
    case :erlang.decode_packet(:http_bin, buf, []) do
      {:ok, {:http_request, method, uri, {major, minor}}, rest} ->
        {:ok, to_method(method), to_uri(uri), "HTTP/#{major}.#{minor}", rest}

      {:ok, {:http_error, line}, _rest} ->
        {:error, {:bad_request_line, line}}

      {:more, _} ->
        case read_more(socket, transport, buf, timeout, @max_header_bytes) do
          {:ok, buf2} -> read_request_line(socket, transport, buf2, timeout)
          {:error, _} = err -> err
        end
    end
  end

  defp read_headers(socket, transport, buf, acc, used, timeout) do
    case :erlang.decode_packet(:httph_bin, buf, []) do
      {:ok, :http_eoh, rest} ->
        {:ok, Enum.reverse(acc), rest}

      {:ok, {:http_header, _len, name, _reserved, value}, rest} ->
        header = {to_header_name(name), value}
        read_headers(socket, transport, rest, [header | acc], byte_size(rest), timeout)

      {:ok, {:http_error, line}, _rest} ->
        {:error, {:bad_header, line}}

      {:more, _} ->
        if used >= @max_header_bytes do
          {:error, :header_too_large}
        else
          case read_more(socket, transport, buf, timeout, @max_header_bytes) do
            {:ok, buf2} -> read_headers(socket, transport, buf2, acc, byte_size(buf2), timeout)
            {:error, _} = err -> err
          end
        end
    end
  end

  defp read_more(socket, transport, buf, timeout, max_bytes) do
    if byte_size(buf) >= max_bytes do
      {:error, :header_too_large}
    else
      case transport.recv(socket, 0, timeout) do
        {:ok, data} -> {:ok, buf <> data}
        {:error, _} = err -> err
      end
    end
  end

  defp to_method(method) when is_atom(method), do: method |> Atom.to_string() |> String.upcase()
  defp to_method(method) when is_binary(method), do: String.upcase(method)

  defp to_uri({:absoluteURI, _scheme, _host, _port, _path} = uri), do: stringify_uri(uri)
  defp to_uri({:scheme, _scheme, _string} = uri), do: stringify_uri(uri)
  defp to_uri({:abs_path, path}), do: path
  defp to_uri(~c"*"), do: "*"
  defp to_uri(uri) when is_binary(uri), do: uri
  defp to_uri(uri) when is_list(uri), do: List.to_string(uri)

  defp stringify_uri({:absoluteURI, scheme, host, :undefined, path}) do
    "#{scheme}://#{host}#{path}"
  end

  defp stringify_uri({:absoluteURI, scheme, host, port, path}) do
    "#{scheme}://#{host}:#{port}#{path}"
  end

  defp stringify_uri({:scheme, scheme, rest}) do
    "#{scheme}:#{rest}"
  end

  defp to_header_name(name) when is_atom(name), do: name |> Atom.to_string() |> String.downcase()
  defp to_header_name(name) when is_binary(name), do: String.downcase(name)
end
