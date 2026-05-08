# edge_agent/lib/edge_agent/proxy_servers/http/parser.ex
defmodule EdgeAgent.ProxyServers.Http.Parser do
  @moduledoc """
  HTTP/1.x request parser built on `:erlang.decode_packet/3`.

  Handles:
    * CRLF and LF line endings
    * Header line folding
    * Case-insensitive header names (lowercased on parse)
    * Max header size limit (default 64 KiB) to defend against slowloris
  """

  @max_header_bytes 64 * 1024

  @type request :: %{
          method: String.t(),
          uri: String.t(),
          version: String.t(),
          headers: [{String.t(), String.t()}]
        }

  @spec read_request(any(), module(), timeout()) :: {:ok, request(), binary()} | {:error, term()}
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

  @doc false
  # Public for unit testing. :erlang.decode_packet returns method as either
  # an atom (well-known methods like :GET) or a binary (custom methods).
  # Normalised to an uppercase string.
  @spec to_method(atom() | binary()) :: String.t()
  def to_method(method) when is_atom(method), do: method |> Atom.to_string() |> String.upcase()
  def to_method(method) when is_binary(method), do: String.upcase(method)

  @doc false
  # Public for unit testing. :erlang.decode_packet returns the URI in five
  # different shapes depending on the request line form. Normalised to a
  # plain string.
  @spec to_uri(term()) :: String.t()
  def to_uri({:absoluteURI, _scheme, _host, _port, _path} = uri), do: stringify_uri(uri)
  def to_uri({:scheme, _scheme, _string} = uri), do: stringify_uri(uri)
  def to_uri({:abs_path, path}), do: path
  def to_uri(~c"*"), do: "*"
  def to_uri(uri) when is_binary(uri), do: uri
  def to_uri(uri) when is_list(uri), do: List.to_string(uri)

  @doc false
  # Public for unit testing. Renders the absoluteURI / scheme tuples returned
  # by :erlang.decode_packet back into a plain URI string.
  @spec stringify_uri(tuple()) :: String.t()
  def stringify_uri({:absoluteURI, scheme, host, :undefined, path}) do
    "#{scheme}://#{host}#{path}"
  end

  def stringify_uri({:absoluteURI, scheme, host, port, path}) do
    "#{scheme}://#{host}:#{port}#{path}"
  end

  def stringify_uri({:scheme, scheme, rest}) do
    "#{scheme}:#{rest}"
  end

  @doc false
  # Public for unit testing. :erlang.decode_packet returns header names as
  # atoms (well-known) or binaries (custom). Normalised to a lowercase
  # string for downstream case-insensitive matching.
  @spec to_header_name(atom() | binary()) :: String.t()
  def to_header_name(name) when is_atom(name), do: name |> Atom.to_string() |> String.downcase()
  def to_header_name(name) when is_binary(name), do: String.downcase(name)
end
