# edge_agent/lib/edge_agent/metrics_servers/network.ex
defmodule EdgeAgent.MetricsServers.Network do
  @moduledoc """
  Network utility functions for the metrics server.

  Handles IP address detection and network interface queries.
  """

  @type ip_result :: {:ok, String.t()} | {:error, term()}

  @spec detect_primary_interface_ip() :: String.t() | nil
  def detect_primary_interface_ip do
    detect_via_ip_route() ||
      detect_via_default_route() ||
      detect_via_interfaces()
  end

  @spec get_interface_ip(String.t()) :: String.t() | nil
  def get_interface_ip(interface) do
    case System.cmd("ip", ["addr", "show", interface], stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.run(~r/inet\s+(\d+\.\d+\.\d+\.\d+)/, output) do
          [_, ip] -> ip
          _ -> nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  # Private functions

  defp detect_via_ip_route do
    case System.cmd("ip", ["route", "get", "8.8.8.8"], stderr_to_stdout: true) do
      {output, 0} ->
        # Parse output like: "8.8.8.8 via 192.168.1.1 dev eth0 src 192.168.1.100 uid 1000"
        case Regex.run(~r/src\s+(\d+\.\d+\.\d+\.\d+)/, output) do
          [_, ip] -> ip
          _ -> nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp detect_via_default_route do
    case System.cmd("ip", ["route", "show", "default"], stderr_to_stdout: true) do
      {output, 0} ->
        # Parse output like: "default via 192.168.1.1 dev eth0 proto dhcp src 192.168.1.100 metric 100"
        case Regex.run(~r/dev\s+(\w+)/, output) do
          [_, interface] ->
            get_interface_ip(interface)

          _ ->
            nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp detect_via_interfaces do
    case System.cmd("ip", ["addr", "show"], stderr_to_stdout: true) do
      {output, 0} ->
        # `ip addr show` output is per-interface — group lines into
        # interface blocks so we can skip wg* / docker* / br-* / veth*
        # interfaces wholesale rather than picking up their inet line.
        output
        |> split_into_interfaces()
        |> Enum.reject(&excluded_interface?/1)
        |> Enum.find_value(&first_global_inet/1)

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  # `ip addr show` starts each interface block with `<index>: <name>:`. Split
  # on those header lines so each chunk carries the interface header plus its
  # inet/inet6 entries.
  defp split_into_interfaces(output) do
    String.split(output, ~r/\n(?=\d+:\s+\S+:)/, trim: true)
  end

  defp excluded_interface?(block) do
    case Regex.run(~r/^\d+:\s+(\S+?):/, block) do
      [_, name] ->
        # Loopback, WireGuard, Docker bridges, veth pairs.
        name == "lo" or
          String.starts_with?(name, "wg") or
          String.starts_with?(name, "docker") or
          String.starts_with?(name, "br-") or
          String.starts_with?(name, "veth")

      _ ->
        false
    end
  end

  defp first_global_inet(block) do
    block
    |> String.split("\n")
    |> Enum.find_value(&extract_ip_from_line/1)
  end

  defp extract_ip_from_line(line) do
    case Regex.run(~r/inet\s+(\d+\.\d+\.\d+\.\d+)\/\d+.+scope global/, line) do
      [_, ip] when ip != "127.0.0.1" -> ip
      _ -> nil
    end
  end
end
