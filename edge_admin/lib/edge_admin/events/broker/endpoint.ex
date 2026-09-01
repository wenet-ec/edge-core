# edge_admin/lib/edge_admin/events/broker/endpoint.ex
defmodule EdgeAdmin.Events.Broker.Endpoint do
  @moduledoc "Pure parsing helpers for broker endpoint environment variables."

  @doc """
  Parses a comma-separated list of `host:port` endpoints.

  Bracketed IPv6 hosts are accepted, as are optional URI schemes such as
  `mqtt://`. The result is suitable for clients that expect `{host, port}`.
  """
  @spec parse_list(String.t(), pos_integer()) :: {:ok, [{String.t(), pos_integer()}]} | {:error, String.t()}
  def parse_list(value, default_port) when is_binary(value) and is_integer(default_port) do
    endpoints = value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    if endpoints == [] do
      {:error, "endpoint list must not be empty"}
    else
      endpoints
      |> Enum.reduce_while({:ok, []}, fn endpoint, {:ok, acc} ->
        case parse(endpoint, default_port) do
          {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
          {:error, reason} -> {:halt, {:error, "invalid endpoint #{inspect(endpoint)}: #{reason}"}}
        end
      end)
      |> case do
        {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
        error -> error
      end
    end
  end

  @doc false
  @spec parse(String.t(), pos_integer()) :: {:ok, {String.t(), pos_integer()}} | {:error, String.t()}
  def parse(endpoint, default_port) do
    uri = URI.parse(if String.contains?(endpoint, "://"), do: endpoint, else: "tcp://" <> endpoint)
    host = uri.host
    authority = endpoint |> String.split("://", parts: 2) |> List.last() |> String.split("/", parts: 2) |> hd()

    cond do
      is_nil(host) or host == "" -> {:error, "host is missing"}
      uri.path not in [nil, "", "/"] -> {:error, "paths are not supported"}
      true -> parse_port(authority, host, uri.port || default_port)
    end
  rescue
    ArgumentError -> {:error, "malformed endpoint"}
  end

  defp parse_port(<<"[", _::binary>> = authority, host, default_port) do
    case Regex.run(~r/\A\[[^\]]+\](?::([^:]+))?\z/, authority) do
      [_, ""] -> {:error, "port must be between 1 and 65535"}
      [_, port] -> validate_port(port, host)
      [_] -> {:ok, {host, default_port}}
      nil -> {:error, "malformed endpoint"}
    end
  end

  defp parse_port(authority, host, default_port) do
    case String.split(authority, ":", parts: 2) do
      [_host] -> {:ok, {host, default_port}}
      [_host, port] -> validate_port(port, host)
    end
  end

  defp validate_port(port, host) do
    case Integer.parse(port) do
      {value, ""} when value in 1..65_535 -> {:ok, {host, value}}
      _ -> {:error, "port must be between 1 and 65535"}
    end
  end
end
