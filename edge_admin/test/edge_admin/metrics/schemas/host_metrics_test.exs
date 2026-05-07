# edge_admin/test/edge_admin/metrics/schemas/host_metrics_test.exs
defmodule EdgeAdmin.Metrics.Schemas.HostMetricsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Metrics.Schemas.HostMetrics
  alias EdgeAdmin.Metrics.Schemas.HostMetrics.CPU
  alias EdgeAdmin.Metrics.Schemas.HostMetrics.Disk
  alias EdgeAdmin.Metrics.Schemas.HostMetrics.Memory
  alias EdgeAdmin.Metrics.Schemas.HostMetrics.Uptime

  # 1 GiB in bytes
  @gib 1_073_741_824

  # ---------------------------------------------------------------------------
  # HostMetrics.from_raw_metrics/2
  # ---------------------------------------------------------------------------

  describe "from_raw_metrics/2" do
    test "produces a struct with node_id, cluster_name, fresh timestamp, and all sub-structs" do
      raw = %{"cluster_name" => "cluster-a"}

      before = DateTime.utc_now()
      result = HostMetrics.from_raw_metrics(raw, "node-abc")
      after_ = DateTime.utc_now()

      assert %HostMetrics{} = result
      assert result.node_id == "node-abc"
      assert result.cluster_name == "cluster-a"
      assert %CPU{} = result.cpu
      assert %Memory{} = result.memory
      assert %Disk{} = result.disk
      assert %Uptime{} = result.uptime
      assert DateTime.compare(result.timestamp, before) in [:gt, :eq]
      assert DateTime.compare(result.timestamp, after_) in [:lt, :eq]
    end

    test "passes nil cluster_name through when missing" do
      result = HostMetrics.from_raw_metrics(%{}, "node-abc")
      assert result.cluster_name == nil
    end
  end

  # ---------------------------------------------------------------------------
  # CPU.from_raw/1
  # ---------------------------------------------------------------------------

  describe "CPU.from_raw/1" do
    test "truncates cpu_cores and rounds load averages to 2dp" do
      raw = %{
        "cpu_cores" => 4.0,
        "load_1m" => 0.4242,
        "load_5m" => 0.8181,
        "load_15m" => 1.2345
      }

      assert CPU.from_raw(raw) == %CPU{
               cores: 4,
               load_1m: 0.42,
               load_5m: 0.82,
               load_15m: 1.23
             }
    end

    test "all fields nil when raw map is empty" do
      assert CPU.from_raw(%{}) == %CPU{cores: nil, load_1m: nil, load_5m: nil, load_15m: nil}
    end

    test "trunc keeps integers as-is" do
      assert CPU.from_raw(%{"cpu_cores" => 8}).cores == 8
    end
  end

  # ---------------------------------------------------------------------------
  # Memory.from_raw/1
  # ---------------------------------------------------------------------------

  describe "Memory.from_raw/1" do
    test "computes used_bytes = total - available, and the GB fields round to 1dp" do
      raw = %{
        "memory_usage_percent" => 50.123,
        "memory_total_bytes" => 8 * @gib,
        "memory_available_bytes" => 4 * @gib
      }

      result = Memory.from_raw(raw)

      assert result.usage_percent == 50.12
      assert result.total_bytes == 8 * @gib
      assert result.available_bytes == 4 * @gib
      assert result.used_bytes == 4 * @gib
      assert result.total_gb == 8.0
      assert result.available_gb == 4.0
      assert result.used_gb == 4.0
    end

    test "used_bytes and used_gb are nil when total or available is missing" do
      result = Memory.from_raw(%{"memory_total_bytes" => 8 * @gib})

      assert result.total_bytes == 8 * @gib
      assert result.available_bytes == nil
      assert result.used_bytes == nil
      assert result.total_gb == 8.0
      assert result.available_gb == nil
      assert result.used_gb == nil
    end

    test "all fields nil when raw map is empty" do
      result = Memory.from_raw(%{})

      assert result.usage_percent == nil
      assert result.total_bytes == nil
      assert result.available_bytes == nil
      assert result.used_bytes == nil
      assert result.total_gb == nil
      assert result.available_gb == nil
      assert result.used_gb == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Disk.from_raw/1
  # ---------------------------------------------------------------------------

  describe "Disk.from_raw/1" do
    test "computes used_bytes = total - available, and the GB fields round to 1dp" do
      raw = %{
        "disk_usage_percent" => 75.456,
        "disk_total_bytes" => 100 * @gib,
        "disk_available_bytes" => 25 * @gib
      }

      result = Disk.from_raw(raw)

      assert result.usage_percent == 75.46
      assert result.total_bytes == 100 * @gib
      assert result.available_bytes == 25 * @gib
      assert result.used_bytes == 75 * @gib
      assert result.total_gb == 100.0
      assert result.available_gb == 25.0
      assert result.used_gb == 75.0
    end

    test "all fields nil when raw map is empty" do
      assert Disk.from_raw(%{}) == %Disk{
               usage_percent: nil,
               total_bytes: nil,
               available_bytes: nil,
               used_bytes: nil,
               total_gb: nil,
               available_gb: nil,
               used_gb: nil
             }
    end
  end

  # ---------------------------------------------------------------------------
  # Uptime.from_raw/1
  # ---------------------------------------------------------------------------

  describe "Uptime.from_raw/1" do
    test "format under 60s → seconds suffix" do
      assert Uptime.from_raw(%{"uptime_seconds" => 42.0}) == %Uptime{seconds: 42, human: "42s"}
      assert Uptime.from_raw(%{"uptime_seconds" => 0}) == %Uptime{seconds: 0, human: "0s"}
    end

    test "format under 1h → minutes suffix" do
      # 5 min 30 sec → "5m"
      assert Uptime.from_raw(%{"uptime_seconds" => 330}).human == "5m"
      # exactly 60s → "1m"
      assert Uptime.from_raw(%{"uptime_seconds" => 60}).human == "1m"
    end

    test "format under 1d → hours and minutes" do
      # 1h 0m
      assert Uptime.from_raw(%{"uptime_seconds" => 3600}).human == "1h 0m"
      # 2h 30m
      assert Uptime.from_raw(%{"uptime_seconds" => 2 * 3600 + 30 * 60}).human == "2h 30m"
    end

    test "format ≥ 1d → days, hours, minutes" do
      assert Uptime.from_raw(%{"uptime_seconds" => 86_400}).human == "1d 0h 0m"
      assert Uptime.from_raw(%{"uptime_seconds" => 3 * 86_400 + 5 * 3600 + 17 * 60}).human == "3d 5h 17m"
    end

    test "uptime_seconds nil → both fields nil" do
      assert Uptime.from_raw(%{}) == %Uptime{seconds: nil, human: nil}
    end

    test "trunc applies before formatting (fractional seconds are dropped)" do
      result = Uptime.from_raw(%{"uptime_seconds" => 90.9})
      assert result.seconds == 90
      assert result.human == "1m"
    end
  end
end
