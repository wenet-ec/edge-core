# edge_admin/test/edge_admin/metrics/schemas/admin_metrics_test.exs
defmodule EdgeAdmin.Metrics.Schemas.AdminMetricsTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Metrics.Schemas.AdminMetrics
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.Application, as: App
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.Commands
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.Discovery
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.EventBroker
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.Gateways
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.Membership
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.Metadata
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.Nodes
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.ObanQueue
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.Proxy
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.Quantum
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.Reconciliation
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.SelfUpdates
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.Ssh
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.Vpn
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.Webhook

  # ---------------------------------------------------------------------------
  # AdminMetrics.from_raw_metrics/1
  # ---------------------------------------------------------------------------

  describe "from_raw_metrics/1" do
    test "produces a struct with fresh timestamp and every sub-struct populated" do
      before = DateTime.utc_now()
      result = AdminMetrics.from_raw_metrics(%{})
      after_ = DateTime.utc_now()

      assert %AdminMetrics{} = result
      assert %App{} = result.application
      assert %Metadata{} = result.metadata
      assert %Membership{} = result.membership
      assert %Discovery{} = result.discovery
      assert %Nodes{} = result.nodes
      assert %Quantum{} = result.quantum
      assert %Vpn{} = result.vpn
      assert %Commands{} = result.commands
      assert %Ssh{} = result.ssh
      assert %Reconciliation{} = result.reconciliation
      assert %SelfUpdates{} = result.self_updates
      assert %Gateways{} = result.gateways
      assert %Proxy{} = result.proxy
      assert %EventBroker{} = result.event_broker
      assert %Webhook{} = result.webhook
      assert is_list(result.oban_queues)
      assert DateTime.compare(result.timestamp, before) in [:gt, :eq]
      assert DateTime.compare(result.timestamp, after_) in [:lt, :eq]
    end
  end

  # ---------------------------------------------------------------------------
  # Application — uptime_ms / uptime_seconds + memory MB rounding
  # ---------------------------------------------------------------------------

  describe "Application.from_raw/1" do
    test "uptime_ms → seconds (integer division) and human format covers each range" do
      assert App.from_raw(%{"uptime_ms" => 30_000}).uptime_human == "30s"
      assert App.from_raw(%{"uptime_ms" => 90_000}).uptime_human == "1m"
      assert App.from_raw(%{"uptime_ms" => 3_600_000}).uptime_human == "1h 0m"
      assert App.from_raw(%{"uptime_ms" => 86_400_000}).uptime_human == "1d 0h 0m"
    end

    test "missing uptime_ms → 0s, '0s'" do
      result = App.from_raw(%{})
      assert result.uptime_seconds == 0
      assert result.uptime_human == "0s"
    end

    test "memory MB fields round to 2dp; nil bytes → nil mb" do
      raw = %{"memory_total" => 10 * 1_048_576}
      result = App.from_raw(raw)
      assert result.memory_total_bytes == 10 * 1_048_576
      assert result.memory_total_mb == 10.0

      empty = App.from_raw(%{})
      assert empty.memory_total_mb == nil
      assert empty.memory_processes_mb == nil
      assert empty.memory_ets_mb == nil
      assert empty.memory_binary_mb == nil
      assert empty.memory_code_mb == nil
      assert empty.memory_atom_mb == nil
    end

    test "passes through process_count, port_count, atom_count, ets_count" do
      raw = %{"process_count" => 100, "port_count" => 50, "atom_count" => 12_000, "ets_count" => 30}
      result = App.from_raw(raw)
      assert result.process_count == 100
      assert result.port_count == 50
      assert result.atom_count == 12_000
      assert result.ets_count == 30
    end
  end

  # ---------------------------------------------------------------------------
  # Metadata — degraded boolean coercion
  # ---------------------------------------------------------------------------

  describe "Metadata.from_raw/1" do
    test "metadata_degraded == 1 → true" do
      assert Metadata.from_raw(%{"metadata_degraded" => 1}).degraded == true
    end

    test "metadata_degraded == 0 → false" do
      assert Metadata.from_raw(%{"metadata_degraded" => 0}).degraded == false
    end

    test "metadata_degraded missing → false (nil != 1)" do
      assert Metadata.from_raw(%{}).degraded == false
    end

    test "passes through orphaned_clusters, assigned_clusters, recomputations_total" do
      raw = %{
        "metadata_orphaned_clusters" => 2,
        "metadata_assigned_clusters" => 5,
        "metadata_recomputations" => 17
      }

      result = Metadata.from_raw(raw)
      assert result.orphaned_clusters == 2
      assert result.assigned_clusters == 5
      assert result.recomputations_total == 17
    end
  end

  # ---------------------------------------------------------------------------
  # Proxy — bytes_to_mb(nil) is nil here (different from agent's 0.0 quirk)
  # ---------------------------------------------------------------------------

  describe "Proxy.from_raw/1" do
    test "bytes_to_mb(nil) → nil (not 0.0)" do
      result = Proxy.from_raw(%{})
      assert result.bytes_up_total == nil
      assert result.bytes_down_total == nil
      assert result.bytes_up_mb == nil
      assert result.bytes_down_mb == nil
    end

    test "non-nil bytes round to 2dp" do
      raw = %{
        "proxy_tunnel_bytes_up_total" => 7 * 1_048_576,
        "proxy_tunnel_bytes_down_total" => 1_572_864
      }

      result = Proxy.from_raw(raw)
      assert result.bytes_up_mb == 7.0
      # 1.5 MiB
      assert result.bytes_down_mb == 1.5
    end
  end

  # ---------------------------------------------------------------------------
  # Trivial passthrough sub-modules
  # ---------------------------------------------------------------------------

  describe "passthrough sub-modules" do
    test "Membership passes through both keys" do
      raw = %{"membership_steps" => 4, "membership_complete_total" => 1}

      assert Membership.from_raw(raw) == %Membership{
               steps_completed_total: 4,
               complete_total: 1
             }
    end

    test "Discovery passes through three keys" do
      raw = %{
        "discovery_scans_total" => 10,
        "discovery_dns_resolutions_total" => 8,
        "discovery_peer_connections_total" => 3
      }

      assert Discovery.from_raw(raw) == %Discovery{
               scans_total: 10,
               dns_resolutions_total: 8,
               peer_connections_total: 3
             }
    end

    test "Nodes / Quantum / Vpn / Ssh / Reconciliation / SelfUpdates / Gateways pass missing keys as nil" do
      assert Nodes.from_raw(%{}).health_checks_total == nil
      assert Quantum.from_raw(%{}).jobs_executed_total == nil
      assert Vpn.from_raw(%{}).zombie_cleanup_total == nil
      assert Ssh.from_raw(%{}).verifications_total == nil
      assert Reconciliation.from_raw(%{}).total == nil
      assert SelfUpdates.from_raw(%{}).completed_total == nil
      assert Gateways.from_raw(%{}).active_count == nil
    end

    test "Webhook counters pass through" do
      raw = %{
        "webhook_fan_outs_total" => 1,
        "webhook_deliveries_total" => 5,
        "webhook_deliveries_ok_total" => 4,
        "webhook_deliveries_recoverable_total" => 1,
        "webhook_deliveries_terminal_total" => 0
      }

      assert Webhook.from_raw(raw) == %Webhook{
               fan_outs_total: 1,
               deliveries_total: 5,
               deliveries_ok_total: 4,
               deliveries_recoverable_total: 1,
               deliveries_terminal_total: 0
             }
    end
  end

  # ---------------------------------------------------------------------------
  # EventBroker — `enabled` is a boolean (sourced from app config), counters pass through
  # ---------------------------------------------------------------------------

  describe "EventBroker.from_raw/1" do
    test "enabled is a boolean (driven by :event_broker_enabled config)" do
      assert is_boolean(EventBroker.from_raw(%{}).enabled)
    end

    test "passes through all counters" do
      raw = %{
        "event_broker_enqueues_total" => 7,
        "event_broker_publishes_total" => 6,
        "event_broker_publishes_ok_total" => 5,
        "event_broker_publishes_error_total" => 1
      }

      result = EventBroker.from_raw(raw)
      assert result.enqueues_total == 7
      assert result.publishes_total == 6
      assert result.publishes_ok_total == 5
      assert result.publishes_error_total == 1
    end
  end

  # ---------------------------------------------------------------------------
  # ObanQueue — flat shape (no nested "states" wrapper, unlike AgentMetrics)
  # ---------------------------------------------------------------------------

  describe "ObanQueue.from_raw/1" do
    test "maps each queue entry into a struct (admin shape: counters at top level)" do
      raw = %{
        "oban_queues" => [
          %{
            "queue" => "default",
            "available" => 1,
            "scheduled" => 2,
            "executing" => 3,
            "retryable" => 4,
            "completed" => 5,
            "discarded" => 6,
            "cancelled" => 7
          }
        ]
      }

      assert ObanQueue.from_raw(raw) == [
               %ObanQueue{
                 queue: "default",
                 available: 1,
                 scheduled: 2,
                 executing: 3,
                 retryable: 4,
                 completed: 5,
                 discarded: 6,
                 cancelled: 7
               }
             ]
    end

    test "missing oban_queues key → empty list" do
      assert ObanQueue.from_raw(%{}) == []
    end
  end
end
