# edge_admin/lib/edge_admin/nodes/prometheus_parser.ex
defmodule EdgeAdmin.Nodes.PrometheusParser do
  @moduledoc """
  Parses Prometheus text format metrics from node_exporter.

  Extracts instant values for CPU, memory, disk, network, and uptime metrics.
  """

  @doc """
  Parses raw Prometheus text format and extracts metrics.

  Returns a map with metric keys that can be used to build the Metrics schema.
  """
  def parse(prometheus_text) do
    lines = String.split(prometheus_text, "\n", trim: true)

    metrics = %{}

    metrics
    |> parse_cpu_metrics(lines)
    |> parse_memory_metrics(lines)
    |> parse_disk_metrics(lines)
    |> parse_network_metrics(lines)
    |> parse_uptime_metrics(lines)
  end

  # Parse CPU metrics
  defp parse_cpu_metrics(metrics, lines) do
    # Extract CPU cores
    cores = parse_metric_value(lines, ~r/^node_cpu_seconds_total\{cpu="(\d+)"/)
    |> case do
      cpu_list when is_list(cpu_list) and length(cpu_list) > 0 ->
        cpu_list |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length()
      _ -> nil
    end

    # Extract load averages
    load_1m = parse_single_metric(lines, "node_load1")
    load_5m = parse_single_metric(lines, "node_load5")
    load_15m = parse_single_metric(lines, "node_load15")

    Map.merge(metrics, %{
      "cpu_cores" => cores,
      "load_1m" => load_1m,
      "load_5m" => load_5m,
      "load_15m" => load_15m
      # Note: cpu_usage_percent requires rate calculation, not available from instant values
    })
  end

  # Parse memory metrics
  defp parse_memory_metrics(metrics, lines) do
    total = parse_single_metric(lines, "node_memory_MemTotal_bytes")
    available = parse_single_metric(lines, "node_memory_MemAvailable_bytes")

    usage_percent = if total && available && total > 0 do
      ((total - available) / total) * 100
    end

    Map.merge(metrics, %{
      "memory_total_bytes" => total,
      "memory_available_bytes" => available,
      "memory_usage_percent" => usage_percent
    })
  end

  # Parse disk metrics (root filesystem only for simplicity)
  defp parse_disk_metrics(metrics, lines) do
    # Find root filesystem metrics
    total = parse_metric_with_label(lines, "node_filesystem_size_bytes", ~r/mountpoint="\/"/)
    available = parse_metric_with_label(lines, "node_filesystem_avail_bytes", ~r/mountpoint="\/"/)


    usage_percent = if total && available && total > 0 do
      ((total - available) / total) * 100
    end

    Map.merge(metrics, %{
      "disk_total_bytes" => total,
      "disk_available_bytes" => available,
      "disk_usage_percent" => usage_percent
    })
  end

  # Parse network metrics (eth0 interface, instant values only)
  defp parse_network_metrics(metrics, lines) do
    # Note: These are total counters, not rates
    # We can't calculate bytes/sec without time series data
    rx_total = parse_metric_with_label(lines, "node_network_receive_bytes_total", ~r/device="eth0"/)
    tx_total = parse_metric_with_label(lines, "node_network_transmit_bytes_total", ~r/device="eth0"/)

    Map.merge(metrics, %{
      "network_rx_total_bytes" => rx_total,
      "network_tx_total_bytes" => tx_total
      # Note: rx/tx_bytes_per_sec requires rate calculation, not available from instant values
    })
  end

  # Parse uptime metrics
  defp parse_uptime_metrics(metrics, lines) do
    boot_time = parse_single_metric(lines, "node_boot_time_seconds")

    uptime_seconds = if boot_time do
      System.system_time(:second) - trunc(boot_time)
    end

    Map.merge(metrics, %{
      "uptime_seconds" => uptime_seconds
    })
  end

  # Helper: Parse a simple metric without labels
  defp parse_single_metric(lines, metric_name) do
    lines
    |> Enum.find_value(fn line ->
      case Regex.run(~r/^#{Regex.escape(metric_name)}\s+([\d.eE+-]+)/, line) do
        [_, value] -> parse_float(value)
        nil -> nil
      end
    end)
  end

  defp parse_float(value) do
    case Float.parse(value) do
      {float_val, _} -> float_val
      :error -> nil
    end
  end

  # Helper: Parse a metric with specific label filter
  defp parse_metric_with_label(lines, metric_name, label_regex) do
    lines
    |> Enum.find_value(fn line ->
      if String.starts_with?(line, metric_name) && Regex.match?(label_regex, line) do
        case Regex.run(~r/}\s+([\d.eE+-]+)/, line) do
          [_, value] -> parse_float(value)
          nil -> nil
        end
      end
    end)
  end

  # Helper: Parse metric value with regex capture
  defp parse_metric_value(lines, regex) do
    lines
    |> Enum.flat_map(fn line ->
      case Regex.scan(regex, line) do
        [] -> []
        matches -> matches |> Enum.map(fn [_, cpu] -> {cpu, true} end)
      end
    end)
  end
end
