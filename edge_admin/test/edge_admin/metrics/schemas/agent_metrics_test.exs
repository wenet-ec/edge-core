# edge_admin/test/edge_admin/metrics/schemas/agent_metrics_test.exs
defmodule EdgeAdmin.Metrics.Schemas.AgentMetricsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Metrics.Schemas.AgentMetrics
  alias EdgeAdmin.Metrics.Schemas.AgentMetrics.Application, as: App
  alias EdgeAdmin.Metrics.Schemas.AgentMetrics.Commands
  alias EdgeAdmin.Metrics.Schemas.AgentMetrics.Discovery
  alias EdgeAdmin.Metrics.Schemas.AgentMetrics.HealthCheck
  alias EdgeAdmin.Metrics.Schemas.AgentMetrics.ObanQueue
  alias EdgeAdmin.Metrics.Schemas.AgentMetrics.Proxy
  alias EdgeAdmin.Metrics.Schemas.AgentMetrics.Ssh
  alias EdgeAdmin.Metrics.Schemas.AgentMetrics.Vpn

  # ---------------------------------------------------------------------------
  # AgentMetrics.from_raw_metrics/2
  # ---------------------------------------------------------------------------

  describe "from_raw_metrics/2" do
    test "produces a struct with node_id, cluster_name, fresh timestamp, and all sub-structs" do
      raw = %{"cluster_name" => "cluster-a"}

      before = DateTime.utc_now()
      result = AgentMetrics.from_raw_metrics(raw, "node-abc")
      after_ = DateTime.utc_now()

      assert %AgentMetrics{} = result
      assert result.node_id == "node-abc"
      assert result.cluster_name == "cluster-a"
      assert %App{} = result.application
      assert %Commands{} = result.commands
      assert %Discovery{} = result.discovery
      assert %Proxy{} = result.proxy
      assert %Ssh{} = result.ssh
      assert %Vpn{} = result.vpn
      assert %HealthCheck{} = result.health_check
      assert is_list(result.oban_queues)
      assert DateTime.compare(result.timestamp, before) in [:gt, :eq]
      assert DateTime.compare(result.timestamp, after_) in [:lt, :eq]
    end
  end

  # ---------------------------------------------------------------------------
  # Application — uptime conversion + memory bytes_to_mb
  # ---------------------------------------------------------------------------

  describe "Application.from_raw/1" do
    test "converts uptime_ms to seconds (integer division) and formats human string" do
      # 90,000 ms → 90s → "1m"
      result = App.from_raw(%{"uptime_ms" => 90_000})
      assert result.uptime_seconds == 90
      assert result.uptime_human == "1m"
    end

    test "uptime_ms nil → 0 seconds, '0s'" do
      result = App.from_raw(%{})
      assert result.uptime_seconds == 0
      assert result.uptime_human == "0s"
    end

    test "uptime_ms truncates fractional milliseconds (div is integer)" do
      # 999 ms → 0s
      assert App.from_raw(%{"uptime_ms" => 999}).uptime_seconds == 0
    end

    test "memory bytes are passed through, MB fields round to 2dp" do
      # 10 MiB exactly
      result = App.from_raw(%{"memory_total" => 10 * 1_048_576})
      assert result.memory_total_bytes == 10 * 1_048_576
      assert result.memory_total_mb == 10.0
    end

    test "memory MB fields are nil when raw bytes are nil" do
      result = App.from_raw(%{})
      assert result.memory_total_mb == nil
      assert result.memory_processes_mb == nil
      assert result.memory_ets_mb == nil
      assert result.memory_binary_mb == nil
    end

    test "passes through process_count" do
      assert App.from_raw(%{"process_count" => 1234}).process_count == 1234
    end

    test "format_uptime ranges (via Application path: uptime_ms = seconds * 1000)" do
      assert App.from_raw(%{"uptime_ms" => 30_000}).uptime_human == "30s"
      assert App.from_raw(%{"uptime_ms" => 3_600_000}).uptime_human == "1h 0m"
      assert App.from_raw(%{"uptime_ms" => 86_400_000}).uptime_human == "1d 0h 0m"
    end
  end

  # ---------------------------------------------------------------------------
  # Commands / Discovery / Ssh / Vpn / HealthCheck — passthrough with `|| 0`
  # ---------------------------------------------------------------------------

  describe "passthrough sub-modules default missing keys to 0" do
    test "Commands defaults all counters to 0" do
      assert Commands.from_raw(%{}) == %Commands{
               synced_total: 0,
               enqueued_total: 0,
               completed_total: 0,
               reported_total: 0
             }
    end

    test "Commands passes values through when present" do
      raw = %{
        "commands_synced" => 1,
        "commands_enqueued" => 2,
        "commands_completed" => 3,
        "commands_reported" => 4
      }

      assert Commands.from_raw(raw) == %Commands{
               synced_total: 1,
               enqueued_total: 2,
               completed_total: 3,
               reported_total: 4
             }
    end

    test "Discovery defaults to 0" do
      assert Discovery.from_raw(%{}) == %Discovery{scans_total: 0, admins_found_last: 0}
    end

    test "Ssh defaults to 0" do
      assert Ssh.from_raw(%{}) == %Ssh{authentications_total: 0, connections_total: 0}
    end

    test "Vpn defaults to 0" do
      assert Vpn.from_raw(%{}) == %Vpn{pulls_total: 0}
    end

    test "HealthCheck defaults to 0" do
      assert HealthCheck.from_raw(%{}) == %HealthCheck{reports_total: 0}
    end
  end

  # ---------------------------------------------------------------------------
  # Proxy — bytes math, the bytes_to_mb(0) == 0.0 quirk
  # ---------------------------------------------------------------------------

  describe "Proxy.from_raw/1" do
    test "bytes_to_mb(0) returns 0.0 (not 0 integer)" do
      result = Proxy.from_raw(%{})
      assert result.bytes_up_total == 0
      assert result.bytes_down_total == 0
      # Specifically guarded by the bytes_to_mb(0) clause.
      assert result.bytes_up_mb === 0.0
      assert result.bytes_down_mb === 0.0
    end

    test "non-zero bytes round to 2dp" do
      raw = %{
        "proxy_tunnel_bytes_up_total" => 5 * 1_048_576,
        "proxy_tunnel_bytes_down_total" => 1024 * 1024 * 3
      }

      result = Proxy.from_raw(raw)
      assert result.bytes_up_mb == 5.0
      assert result.bytes_down_mb == 3.0
    end

    test "blocked_by_reason maps default to %{}" do
      result = Proxy.from_raw(%{})
      assert result.http_blocked_by_reason == %{}
      assert result.socks5_blocked_by_reason == %{}
    end

    test "blocked_by_reason maps pass through when present" do
      raw = %{"proxy_http_blocked_by_reason" => %{"deny_list" => 3}}
      assert Proxy.from_raw(raw).http_blocked_by_reason == %{"deny_list" => 3}
    end

    test "all simple counters default to 0" do
      result = Proxy.from_raw(%{})
      assert result.http_connections_total == 0
      assert result.http_blocked_total == 0
      assert result.socks5_connections_total == 0
      assert result.socks5_blocked_total == 0
      assert result.tunnels_closed_total == 0
      assert result.tunnels_closed_normal_total == 0
      assert result.tunnels_closed_deadline_total == 0
      assert result.tunnels_closed_drain_timeout_total == 0
    end
  end

  # ---------------------------------------------------------------------------
  # ObanQueue — list mapping and nested "states" map
  # ---------------------------------------------------------------------------

  describe "ObanQueue.from_raw/1" do
    test "maps each queue entry into a struct with state counters" do
      raw = %{
        "oban_queues" => [
          %{
            "queue" => "default",
            "states" => %{
              "available" => 1,
              "executing" => 2,
              "completed" => 3,
              "discarded" => 4,
              "retryable" => 5
            }
          },
          %{
            "queue" => "events",
            "states" => %{
              "available" => 0,
              "executing" => 0,
              "completed" => 0,
              "discarded" => 0,
              "retryable" => 0
            }
          }
        ]
      }

      assert ObanQueue.from_raw(raw) == [
               %ObanQueue{
                 queue: "default",
                 available: 1,
                 executing: 2,
                 completed: 3,
                 discarded: 4,
                 retryable: 5
               },
               %ObanQueue{
                 queue: "events",
                 available: 0,
                 executing: 0,
                 completed: 0,
                 discarded: 0,
                 retryable: 0
               }
             ]
    end

    test "missing oban_queues key → empty list" do
      assert ObanQueue.from_raw(%{}) == []
    end
  end
end
