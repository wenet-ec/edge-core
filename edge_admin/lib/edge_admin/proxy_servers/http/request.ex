# edge_admin/lib/edge_admin/proxy_servers/http/request.ex
defmodule EdgeAdmin.ProxyServers.Http.Request do
  @moduledoc """
  Pure HTTP proxy request and header transformations used by the Admin handler.
  """

  @hop_by_hop_headers ~w(connection keep-alive proxy-authenticate proxy-authorization proxy-connection te trailer transfer-encoding upgrade)

  @spec validate_proxy_form(String.t(), String.t()) :: :ok | {:error, :origin_form_uri}
  def validate_proxy_form("CONNECT", _uri), do: :ok

  def validate_proxy_form(_method, uri) do
    case URI.parse(uri) do
      %URI{scheme: scheme, host: host} when is_binary(scheme) and is_binary(host) -> :ok
      _ -> {:error, :origin_form_uri}
    end
  end

  @spec check_loop([{String.t(), String.t()}], String.t()) :: :ok | {:error, :loop_detected}
  def check_loop(headers, pseudonym) do
    case get_header(headers, "via") do
      nil -> :ok
      via -> if String.contains?(via, pseudonym), do: {:error, :loop_detected}, else: :ok
    end
  end

  @spec reconcile_host_header([{String.t(), String.t()}], String.t(), 1..65_535) :: [{String.t(), String.t()}]
  def reconcile_host_header(headers, host, port) do
    value = if port in [80, 443], do: host, else: "#{host}:#{port}"
    [{"host", value} | Enum.reject(headers, fn {key, _} -> String.downcase(key) == "host" end)]
  end

  @spec filter_hop_by_hop_headers([{String.t(), String.t()}]) :: [{String.t(), String.t()}]
  def filter_hop_by_hop_headers(headers) do
    listed =
      headers
      |> get_header("connection")
      |> to_string()
      |> String.split(",", trim: true)
      |> Enum.map(&(&1 |> String.trim() |> String.downcase()))

    drop = MapSet.new(@hop_by_hop_headers ++ listed)
    filtered = Enum.reject(headers, fn {key, _} -> String.downcase(key) in drop end)

    if "upgrade" in listed do
      connection = [{"connection", "Upgrade"} | filtered]

      case get_header(headers, "upgrade") do
        nil -> connection
        upgrade -> [{"upgrade", upgrade} | connection]
      end
    else
      filtered
    end
  end

  @spec add_via_header([{String.t(), String.t()}], String.t(), String.t()) :: [{String.t(), String.t()}]
  def add_via_header(headers, http_version, pseudonym) do
    entry = "#{parse_http_version(http_version)} #{pseudonym}"

    value =
      case get_header(headers, "via") do
        nil -> entry
        existing -> "#{existing}, #{entry}"
      end

    [{"via", value} | Enum.reject(headers, fn {key, _} -> String.downcase(key) == "via" end)]
  end

  @spec parse_http_version(String.t()) :: String.t()
  def parse_http_version("HTTP/1.0"), do: "1.0"
  def parse_http_version("HTTP/1.1"), do: "1.1"
  def parse_http_version("HTTP/" <> rest), do: rest
  def parse_http_version(_), do: "1.1"

  @spec build_http_request(String.t(), String.t(), String.t(), [{String.t(), String.t()}]) :: binary()
  def build_http_request(method, path, version, headers) do
    lines = Enum.map(headers, fn {key, value} -> "#{key}: #{value}\r\n" end)
    IO.iodata_to_binary(["#{method} #{path} #{version}\r\n", lines, "\r\n"])
  end

  @spec parse_http_uri(String.t()) :: {:ok, String.t(), 1..65_535, String.t()} | {:error, :invalid_uri}
  def parse_http_uri(uri) do
    case URI.parse(uri) do
      %URI{scheme: scheme, host: host, port: port, path: path} when scheme in ["http", "https"] and is_binary(host) ->
        {:ok, host, port || if(scheme == "https", do: 443, else: 80), path || "/"}

      _ ->
        {:error, :invalid_uri}
    end
  end

  @spec parse_host_port(String.t()) :: {:ok, String.t(), 1..65_535} | {:error, :invalid_port | :invalid_format}
  def parse_host_port(uri) do
    case String.split(uri, ":", parts: 2) do
      [host, port] ->
        case Integer.parse(port) do
          {number, _} -> {:ok, host, number}
          :error -> {:error, :invalid_port}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  @spec get_header([{String.t(), String.t()}], String.t()) :: String.t() | nil
  def get_header(headers, key) do
    key = String.downcase(key)
    Enum.find_value(headers, fn {name, value} -> if String.downcase(name) == key, do: value end)
  end
end
