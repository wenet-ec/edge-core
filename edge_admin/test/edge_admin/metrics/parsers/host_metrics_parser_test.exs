# edge_admin/test/edge_admin/metrics/parsers/host_metrics_parser_test.exs
defmodule EdgeAdmin.Metrics.Parsers.HostMetricsParserTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Metrics.Parsers.HostMetricsParser
  alias EdgeAdmin.Metrics.Schemas.HostMetrics

  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------

  defp sample_prometheus_text do
    """
    # HELP node_cpu_seconds_total CPU seconds total
    # TYPE node_cpu_seconds_total counter
    node_cpu_seconds_total{cpu="0",mode="idle"} 12345.67
    node_cpu_seconds_total{cpu="0",mode="user"} 234.56
    node_cpu_seconds_total{cpu="1",mode="idle"} 11111.11
    node_cpu_seconds_total{cpu="1",mode="user"} 222.22
    node_cpu_seconds_total{cpu="2",mode="idle"} 10000.00
    node_cpu_seconds_total{cpu="3",mode="idle"} 9000.00
    # HELP node_load1 1m load average
    node_load1 0.42
    node_load5 0.81
    node_load15 1.23
    # HELP node_memory_MemTotal_bytes Total memory
    node_memory_MemTotal_bytes 8589934592
    node_memory_MemAvailable_bytes 4294967296
    # HELP node_filesystem_size_bytes Filesystem size
    node_filesystem_size_bytes{mountpoint="/",fstype="ext4"} 107374182400
    node_filesystem_avail_bytes{mountpoint="/",fstype="ext4"} 53687091200
    node_filesystem_size_bytes{mountpoint="/boot",fstype="vfat"} 1073741824
    node_filesystem_avail_bytes{mountpoint="/boot",fstype="vfat"} 536870912
    # HELP node_network_receive_bytes_total Network receive bytes
    node_network_receive_bytes_total{device="eth0"} 1073741824
    node_network_transmit_bytes_total{device="eth0"} 536870912
    node_network_receive_bytes_total{device="lo"} 999999
    node_boot_time_seconds 1000000000
    """
  end

  defp empty_prometheus_text, do: ""

  # ---------------------------------------------------------------------------
  # parse/1 — CPU metrics
  # ---------------------------------------------------------------------------

  describe "parse/1 — CPU metrics" do
    test "counts unique CPU cores" do
      result = HostMetricsParser.parse(sample_prometheus_text())
      # 4 unique cpu values: "0", "1", "2", "3"
      assert result["cpu_cores"] == 4
    end

    test "extracts load averages" do
      result = HostMetricsParser.parse(sample_prometheus_text())
      assert result["load_1m"] == 0.42
      assert result["load_5m"] == 0.81
      assert result["load_15m"] == 1.23
    end

    test "cpu_cores is nil when no cpu metrics present" do
      result = HostMetricsParser.parse(empty_prometheus_text())
      assert result["cpu_cores"] == nil
    end

    test "load averages are nil when not present" do
      result = HostMetricsParser.parse(empty_prometheus_text())
      assert result["load_1m"] == nil
      assert result["load_5m"] == nil
      assert result["load_15m"] == nil
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — memory metrics
  # ---------------------------------------------------------------------------

  describe "parse/1 — memory metrics" do
    test "extracts total and available memory bytes" do
      result = HostMetricsParser.parse(sample_prometheus_text())
      assert result["memory_total_bytes"] == 8_589_934_592.0
      assert result["memory_available_bytes"] == 4_294_967_296.0
    end

    test "calculates memory usage percent" do
      result = HostMetricsParser.parse(sample_prometheus_text())
      # (8GB - 4GB) / 8GB * 100 = 50.0
      assert result["memory_usage_percent"] == 50.0
    end

    test "memory fields are nil when not present" do
      result = HostMetricsParser.parse(empty_prometheus_text())
      assert result["memory_total_bytes"] == nil
      assert result["memory_available_bytes"] == nil
      assert result["memory_usage_percent"] == nil
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — disk metrics
  # ---------------------------------------------------------------------------

  describe "parse/1 — disk metrics" do
    test "extracts root filesystem size and available bytes" do
      result = HostMetricsParser.parse(sample_prometheus_text())
      assert result["disk_total_bytes"] == 107_374_182_400.0
      assert result["disk_available_bytes"] == 53_687_091_200.0
    end

    test "calculates disk usage percent for root mountpoint" do
      result = HostMetricsParser.parse(sample_prometheus_text())
      # (100GB - 50GB) / 100GB * 100 = 50.0
      assert result["disk_usage_percent"] == 50.0
    end

    test "only extracts root mountpoint (not /boot)" do
      result = HostMetricsParser.parse(sample_prometheus_text())
      # root is 100GB, not 1GB (/boot)
      assert result["disk_total_bytes"] == 107_374_182_400.0
    end

    test "disk fields are nil when not present" do
      result = HostMetricsParser.parse(empty_prometheus_text())
      assert result["disk_total_bytes"] == nil
      assert result["disk_available_bytes"] == nil
      assert result["disk_usage_percent"] == nil
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — network metrics
  # ---------------------------------------------------------------------------

  describe "parse/1 — network metrics" do
    test "extracts eth0 network bytes" do
      result = HostMetricsParser.parse(sample_prometheus_text())
      assert result["network_rx_total_bytes"] == 1_073_741_824.0
      assert result["network_tx_total_bytes"] == 536_870_912.0
    end

    test "ignores non-eth0 interfaces" do
      result = HostMetricsParser.parse(sample_prometheus_text())
      # lo device (999999) should not affect eth0 result
      assert result["network_rx_total_bytes"] == 1_073_741_824.0
    end

    test "network fields are nil when not present" do
      result = HostMetricsParser.parse(empty_prometheus_text())
      assert result["network_rx_total_bytes"] == nil
      assert result["network_tx_total_bytes"] == nil
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — uptime metrics
  # ---------------------------------------------------------------------------

  describe "parse/1 — uptime metrics" do
    test "calculates uptime_seconds from boot_time" do
      result = HostMetricsParser.parse(sample_prometheus_text())
      # uptime = now - boot_time; just assert it's a positive integer
      assert is_integer(result["uptime_seconds"])
      assert result["uptime_seconds"] > 0
    end

    test "uptime_seconds is nil when boot_time not present" do
      result = HostMetricsParser.parse(empty_prometheus_text())
      assert result["uptime_seconds"] == nil
    end
  end

  # ---------------------------------------------------------------------------
  # HostMetrics.from_raw_metrics/2 — struct assembly
  # ---------------------------------------------------------------------------

  describe "HostMetrics.from_raw_metrics/2" do
    test "builds struct with node_id and cluster_name" do
      raw = HostMetricsParser.parse(sample_prometheus_text())
      raw = Map.put(raw, "cluster_name", "prod")

      metrics = HostMetrics.from_raw_metrics(raw, "node-abc")
      assert metrics.node_id == "node-abc"
      assert metrics.cluster_name == "prod"
    end

    test "cpu struct has cores and load averages rounded to 2dp" do
      raw = HostMetricsParser.parse(sample_prometheus_text())
      raw = Map.put(raw, "cluster_name", "prod")

      metrics = HostMetrics.from_raw_metrics(raw, "node-abc")
      assert metrics.cpu.cores == 4
      assert metrics.cpu.load_1m == 0.42
      assert metrics.cpu.load_5m == 0.81
      assert metrics.cpu.load_15m == 1.23
    end

    test "memory struct computes used_bytes and GB values" do
      raw = HostMetricsParser.parse(sample_prometheus_text())
      raw = Map.put(raw, "cluster_name", "prod")

      metrics = HostMetrics.from_raw_metrics(raw, "node-abc")
      assert metrics.memory.total_bytes == 8_589_934_592
      assert metrics.memory.available_bytes == 4_294_967_296
      assert metrics.memory.used_bytes == 4_294_967_296
      assert metrics.memory.total_gb == 8.0
      assert metrics.memory.available_gb == 4.0
      assert metrics.memory.used_gb == 4.0
      assert metrics.memory.usage_percent == 50.0
    end

    test "disk struct computes used_bytes and GB values" do
      raw = HostMetricsParser.parse(sample_prometheus_text())
      raw = Map.put(raw, "cluster_name", "prod")

      metrics = HostMetrics.from_raw_metrics(raw, "node-abc")
      assert metrics.disk.total_bytes == 107_374_182_400
      assert metrics.disk.available_bytes == 53_687_091_200
      assert metrics.disk.used_bytes == 53_687_091_200
      assert metrics.disk.usage_percent == 50.0
    end

    test "nil raw values produce nil struct fields" do
      raw = %{
        "cpu_cores" => nil,
        "load_1m" => nil,
        "load_5m" => nil,
        "load_15m" => nil,
        "memory_total_bytes" => nil,
        "memory_available_bytes" => nil,
        "memory_usage_percent" => nil,
        "disk_total_bytes" => nil,
        "disk_available_bytes" => nil,
        "disk_usage_percent" => nil,
        "network_rx_total_bytes" => nil,
        "network_tx_total_bytes" => nil,
        "uptime_seconds" => nil,
        "cluster_name" => nil
      }

      metrics = HostMetrics.from_raw_metrics(raw, "node-xyz")
      assert metrics.cpu.cores == nil
      assert metrics.cpu.load_1m == nil
      assert metrics.memory.total_bytes == nil
      assert metrics.memory.used_bytes == nil
      assert metrics.memory.total_gb == nil
      assert metrics.disk.total_bytes == nil
      assert metrics.uptime.seconds == nil
      assert metrics.uptime.human == nil
    end
  end

  # ---------------------------------------------------------------------------
  # HostMetrics.Uptime.format_uptime — all branches (via from_raw_metrics)
  # ---------------------------------------------------------------------------

  describe "HostMetrics.Uptime — format_uptime branches" do
    defp uptime_human(seconds) do
      raw = %{
        "cpu_cores" => nil,
        "load_1m" => nil,
        "load_5m" => nil,
        "load_15m" => nil,
        "memory_total_bytes" => nil,
        "memory_available_bytes" => nil,
        "memory_usage_percent" => nil,
        "disk_total_bytes" => nil,
        "disk_available_bytes" => nil,
        "disk_usage_percent" => nil,
        "network_rx_total_bytes" => nil,
        "network_tx_total_bytes" => nil,
        "uptime_seconds" => seconds,
        "cluster_name" => nil
      }

      HostMetrics.from_raw_metrics(raw, "n").uptime.human
    end

    test "seconds only (< 60s)" do
      assert uptime_human(45) == "45s"
    end

    test "minutes only (< 1h)" do
      assert uptime_human(90) == "1m"
      assert uptime_human(3599) == "59m"
    end

    test "hours and minutes (< 1d)" do
      assert uptime_human(3600) == "1h 0m"
      assert uptime_human(3661) == "1h 1m"
      assert uptime_human(86_399) == "23h 59m"
    end

    test "days, hours, and minutes (>= 1d)" do
      assert uptime_human(86_400) == "1d 0h 0m"
      assert uptime_human(90_061) == "1d 1h 1m"
    end
  end
end
