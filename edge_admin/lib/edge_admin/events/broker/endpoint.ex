# edge_admin/lib/edge_admin/events/broker/endpoint.ex
defmodule EdgeAdmin.Events.Broker.Endpoint do
  @moduledoc """Pure parsing helpers for broker endpoint environment variables."""

  @doc """
  Parses a comma-separated list of `host:port` endpoints.

  Bracketed IPv6 hosts are accepted, as are optional URI schemes such as
  `mqtt://`. The result is suitable for clients that expect `{host, port}`.
  """
  @spec parse_list(String.t(), pos_integer()) :: {:ok, [{String.t(), pos_integer()}]} | {:error, String.t()}
  def parse_list(value, default_port) when is_binary(value) and is_integer(default_port) do
    endpoints = String.split(value, ",", trim: true) |> Enum.map(&String.trim/1)

    if endpoints == [] do
      {:error, "endpoint list must not be empty"}
    else
      Enum.reduce_while(endpoints, {:ok, []}, fn endpoint, {:ok, acc} ->
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
    port = uri.port || default_port

    cond do
      is_nil(host) or host == "" -> {:error, "host is missing"}
      not is_integer(port) or port < 1 or port > 65_535 -> {:error, "port must be between 1 and 65535"}
      uri.path not in [nil, "", "/"] -> {:error, "paths are not supported"}
      true -> {:ok, {host, port}}
    end
  rescue
    ArgumentError -> {:error, "malformed endpoint"}
  end
end
