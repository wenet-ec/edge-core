# edge_agent/lib/edge_agent/metrics_servers/network.ex
defmodule EdgeAgent.MetricsServers.Network do
  @moduledoc """
  Network utility functions for the metrics server.

  Handles IP address detection and network interface queries.
  """

  alias EdgeAgent.MetricsServers.Network.Parser

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
        |> Parser.split_into_interfaces()
        |> Enum.reject(&Parser.excluded_interface?/1)
        |> Enum.find_value(&Parser.first_global_inet/1)

      _ ->
        nil
    end
  rescue
    _ -> nil
  end
end
