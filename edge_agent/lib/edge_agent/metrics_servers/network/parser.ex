# edge_agent/lib/edge_agent/metrics_servers/network/parser.ex
defmodule EdgeAgent.MetricsServers.Network.Parser do
  @moduledoc """
  Pure parsers for Linux `ip` command output.
  """

  @doc false
  @spec split_into_interfaces(String.t()) :: [String.t()]
  def split_into_interfaces(output) do
    String.split(output, ~r/\n(?=\d+:\s+\S+:)/, trim: true)
  end

  @doc false
  @spec excluded_interface?(String.t()) :: boolean()
  def excluded_interface?(block) do
    case Regex.run(~r/^\d+:\s+(\S+?):/, block) do
      [_, name] ->
        name == "lo" or
          String.starts_with?(name, "wg") or
          String.starts_with?(name, "docker") or
          String.starts_with?(name, "br-") or
          String.starts_with?(name, "veth")

      _ ->
        false
    end
  end

  @doc false
  @spec first_global_inet(String.t()) :: String.t() | nil
  def first_global_inet(block) do
    block
    |> String.split("\n")
    |> Enum.find_value(&extract_ip_from_line/1)
  end

  @doc false
  @spec extract_ip_from_line(String.t()) :: String.t() | nil
  def extract_ip_from_line(line) do
    case Regex.run(~r/inet\s+(\d+\.\d+\.\d+\.\d+)\/\d+.+scope global/, line) do
      [_, ip] when ip != "127.0.0.1" -> ip
      _ -> nil
    end
  end
end
