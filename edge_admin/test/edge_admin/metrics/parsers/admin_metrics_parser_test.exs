# edge_admin/test/edge_admin/metrics/parsers/admin_metrics_parser_test.exs
defmodule EdgeAdmin.Metrics.Parsers.AdminMetricsParserTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Metrics.Parsers.AdminMetricsParser
  alias EdgeAdmin.Metrics.Schemas.AdminMetrics

  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------

  defp sample_prometheus_text do
    """
    # HELP edge_admin_prom_ex_application_uptime_milliseconds_count Uptime
    edge_admin_prom_ex_application_uptime_milliseconds_count 120000
    edge_admin_prom_ex_beam_stats_process_count 512
    edge_admin_prom_ex_beam_stats_port_count 32
    edge_admin_prom_ex_beam_stats_atom_count 14000
    edge_admin_prom_ex_beam_stats_ets_count 88
    edge_admin_prom_ex_beam_memory_allocated_bytes 104857600
    edge_admin_prom_ex_beam_memory_processes_total_bytes 52428800
    edge_admin_prom_ex_beam_memory_ets_total_bytes 10485760
    edge_admin_prom_ex_beam_memory_binary_total_bytes 5242880
    edge_admin_prom_ex_beam_memory_code_total_bytes 20971520
    edge_admin_prom_ex_beam_memory_atom_total_bytes 1048576
    edge_admin_metadata_degraded 0
    edge_admin_metadata_orphaned_clusters 2
    edge_admin_metadata_assigned_clusters 5
    edge_admin_metadata_recomputation_total{reason="new_admin"} 3
    edge_admin_metadata_recomputation_total{reason="lost_admin"} 1
    edge_admin_bootstrap_step_total{step="vpn"} 1
    edge_admin_bootstrap_step_total{step="db"} 1
    edge_admin_nodes_health_check_total{result="healthy"} 10
    edge_admin_nodes_health_check_total{result="unhealthy"} 2
    edge_admin_quantum_job_executed_total{job="reconcile"} 100
    edge_admin_quantum_job_exception_total{job="reconcile"} 1
    edge_admin_vpn_zombie_admin_cleanup_total{result="ok"} 5
    edge_admin_vpn_zombie_admin_cleanup_deleted_count 3
    edge_admin_commands_delivery_total{result="ok"} 50
    edge_admin_commands_delivery_delivered_count 48
    edge_admin_gateway_connection_total{cluster="prod"} 10
    edge_admin_gateway_connection_total{cluster="staging"} 5
    edge_admin_gateway_active_count 3
    edge_admin_gateway_scrape_total{type="host"} 20
    edge_admin_gateway_scrape_total{type="agent"} 20
    edge_admin_prom_ex_oban_queue_length_count{queue="default",state="available"} 2
    edge_admin_prom_ex_oban_queue_length_count{queue="default",state="executing"} 1
    edge_admin_prom_ex_oban_queue_length_count{queue="default",state="completed"} 100
    edge_admin_prom_ex_oban_queue_length_count{queue="default",state="discarded"} 0
    edge_admin_prom_ex_oban_queue_length_count{queue="default",state="retryable"} 3
    edge_admin_prom_ex_oban_queue_length_count{queue="default",state="scheduled"} 1
    edge_admin_prom_ex_oban_queue_length_count{queue="default",state="cancelled"} 0
    edge_admin_prom_ex_oban_queue_length_count{queue="commands",state="available"} 5
    edge_admin_prom_ex_oban_queue_length_count{queue="commands",state="executing"} 2
    edge_admin_prom_ex_oban_queue_length_count{queue="commands",state="completed"} 200
    edge_admin_prom_ex_oban_queue_length_count{queue="commands",state="discarded"} 1
    edge_admin_prom_ex_oban_queue_length_count{queue="commands",state="retryable"} 0
    edge_admin_prom_ex_oban_queue_length_count{queue="commands",state="scheduled"} 0
    edge_admin_prom_ex_oban_queue_length_count{queue="commands",state="cancelled"} 0
    """
  end

  defp empty_prometheus_text, do: ""

  # ---------------------------------------------------------------------------
  # parse/1 — gauge extraction
  # ---------------------------------------------------------------------------

  describe "parse/1 — gauge extraction" do
    test "extracts uptime_ms" do
      result = AdminMetricsParser.parse(sample_prometheus_text())
      assert result["uptime_ms"] == 120_000
    end

    test "extracts BEAM process and port counts" do
      result = AdminMetricsParser.parse(sample_prometheus_text())
      assert result["process_count"] == 512
      assert result["port_count"] == 32
      assert result["atom_count"] == 14_000
      assert result["ets_count"] == 88
    end

    test "extracts BEAM memory gauges" do
      result = AdminMetricsParser.parse(sample_prometheus_text())
      assert result["memory_total"] == 104_857_600
      assert result["memory_processes"] == 52_428_800
      assert result["memory_ets"] == 10_485_760
      assert result["memory_binary"] == 5_242_880
      assert result["memory_code"] == 20_971_520
      assert result["memory_atom"] == 1_048_576
    end

    test "extracts metadata gauges" do
      result = AdminMetricsParser.parse(sample_prometheus_text())
      assert result["metadata_degraded"] == 0
      assert result["metadata_orphaned_clusters"] == 2
      assert result["metadata_assigned_clusters"] == 5
    end

    test "gauge returns nil when metric not present" do
      result = AdminMetricsParser.parse(empty_prometheus_text())
      assert result["uptime_ms"] == nil
      assert result["process_count"] == nil
      assert result["metadata_degraded"] == nil
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — counter extraction (sums across labels)
  # ---------------------------------------------------------------------------

  describe "parse/1 — counter extraction" do
    test "sums metadata_recomputations across label combinations" do
      result = AdminMetricsParser.parse(sample_prometheus_text())
      # new_admin(3) + lost_admin(1) = 4
      assert result["metadata_recomputations"] == 4
    end

    test "sums bootstrap_steps across label combinations" do
      result = AdminMetricsParser.parse(sample_prometheus_text())
      # vpn(1) + db(1) = 2
      assert result["bootstrap_steps"] == 2
    end

    test "sums nodes_health_checks across label combinations" do
      result = AdminMetricsParser.parse(sample_prometheus_text())
      # healthy(10) + unhealthy(2) = 12
      assert result["nodes_health_checks"] == 12
    end

    test "sums gateway_connections_total across clusters" do
      result = AdminMetricsParser.parse(sample_prometheus_text())
      # prod(10) + staging(5) = 15
      assert result["gateway_connections_total"] == 15
    end

    test "sums gateway_scrapes_total across types" do
      result = AdminMetricsParser.parse(sample_prometheus_text())
      # host(20) + agent(20) = 40
      assert result["gateway_scrapes_total"] == 40
    end

    test "counter returns 0 when metric not present" do
      result = AdminMetricsParser.parse(empty_prometheus_text())
      assert result["metadata_recomputations"] == 0
      assert result["bootstrap_steps"] == 0
      assert result["nodes_health_checks"] == 0
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — Oban queue extraction
  # ---------------------------------------------------------------------------

  describe "parse/1 — Oban queue extraction" do
    test "extracts both queues" do
      result = AdminMetricsParser.parse(sample_prometheus_text())
      queue_names = result["oban_queues"] |> Enum.map(& &1["queue"]) |> Enum.sort()
      assert queue_names == ["commands", "default"]
    end

    test "extracts all 7 states per queue" do
      result = AdminMetricsParser.parse(sample_prometheus_text())
      default_queue = Enum.find(result["oban_queues"], &(&1["queue"] == "default"))
      assert default_queue["available"] == 2
      assert default_queue["executing"] == 1
      assert default_queue["completed"] == 100
      assert default_queue["discarded"] == 0
      assert default_queue["retryable"] == 3
      assert default_queue["scheduled"] == 1
      assert default_queue["cancelled"] == 0
    end

    test "missing state defaults to 0" do
      # Only provide available state for a queue
      text = ~s(edge_admin_prom_ex_oban_queue_length_count{queue="sparse",state="available"} 7\n)
      result = AdminMetricsParser.parse(text)
      sparse_queue = Enum.find(result["oban_queues"], &(&1["queue"] == "sparse"))
      assert sparse_queue["available"] == 7
      assert sparse_queue["executing"] == 0
      assert sparse_queue["completed"] == 0
    end

    test "returns empty list when no Oban metrics present" do
      result = AdminMetricsParser.parse(empty_prometheus_text())
      assert result["oban_queues"] == []
    end
  end

  # ---------------------------------------------------------------------------
  # AdminMetrics.from_raw_metrics/1 — struct assembly
  # ---------------------------------------------------------------------------

  describe "AdminMetrics.from_raw_metrics/1" do
    test "builds all top-level struct fields" do
      raw = AdminMetricsParser.parse(sample_prometheus_text())
      metrics = AdminMetrics.from_raw_metrics(raw)

      assert %AdminMetrics{} = metrics
      assert %AdminMetrics.Application{} = metrics.application
      assert %AdminMetrics.Metadata{} = metrics.metadata
      assert %AdminMetrics.Bootstrap{} = metrics.bootstrap
      assert %AdminMetrics.Nodes{} = metrics.nodes
      assert %AdminMetrics.Quantum{} = metrics.quantum
      assert %AdminMetrics.Vpn{} = metrics.vpn
      assert %AdminMetrics.Commands{} = metrics.commands
      assert %AdminMetrics.Gateways{} = metrics.gateways
      assert is_list(metrics.oban_queues)
    end

    test "application uptime is converted from ms to seconds" do
      raw = AdminMetricsParser.parse(sample_prometheus_text())
      metrics = AdminMetrics.from_raw_metrics(raw)
      # 120000ms / 1000 = 120s
      assert metrics.application.uptime_seconds == 120
    end

    test "application uptime_human formats correctly" do
      raw = AdminMetricsParser.parse(sample_prometheus_text())
      metrics = AdminMetrics.from_raw_metrics(raw)
      assert metrics.application.uptime_human == "2m"
    end

    test "application memory is converted to MB" do
      raw = AdminMetricsParser.parse(sample_prometheus_text())
      metrics = AdminMetrics.from_raw_metrics(raw)
      # 104857600 bytes / 1048576 = 100.0 MB
      assert metrics.application.memory_total_mb == 100.0
    end

    test "metadata degraded is boolean: 0 -> false" do
      raw = AdminMetricsParser.parse(sample_prometheus_text())
      metrics = AdminMetrics.from_raw_metrics(raw)
      assert metrics.metadata.degraded == false
    end

    test "metadata degraded is boolean: 1 -> true" do
      raw = AdminMetricsParser.parse(sample_prometheus_text())
      raw = Map.put(raw, "metadata_degraded", 1)
      metrics = AdminMetrics.from_raw_metrics(raw)
      assert metrics.metadata.degraded == true
    end

    test "metadata cluster counts are preserved" do
      raw = AdminMetricsParser.parse(sample_prometheus_text())
      metrics = AdminMetrics.from_raw_metrics(raw)
      assert metrics.metadata.orphaned_clusters == 2
      assert metrics.metadata.assigned_clusters == 5
      assert metrics.metadata.recomputations_total == 4
    end

    test "gateways active_count and totals are correct" do
      raw = AdminMetricsParser.parse(sample_prometheus_text())
      metrics = AdminMetrics.from_raw_metrics(raw)
      assert metrics.gateways.active_count == 3
      assert metrics.gateways.connections_total == 15
      assert metrics.gateways.scrapes_total == 40
    end

    test "oban_queues is a list of ObanQueue structs" do
      raw = AdminMetricsParser.parse(sample_prometheus_text())
      metrics = AdminMetrics.from_raw_metrics(raw)
      assert length(metrics.oban_queues) == 2
      assert Enum.all?(metrics.oban_queues, &match?(%AdminMetrics.ObanQueue{}, &1))
    end

    test "nil uptime_ms defaults to 0 seconds" do
      raw = AdminMetricsParser.parse(empty_prometheus_text())
      metrics = AdminMetrics.from_raw_metrics(raw)
      assert metrics.application.uptime_seconds == 0
      assert metrics.application.uptime_human == "0s"
    end
  end

  # ---------------------------------------------------------------------------
  # AdminMetrics.Application.format_uptime — all branches
  # ---------------------------------------------------------------------------

  describe "AdminMetrics.Application — format_uptime branches" do
    defp uptime_human(ms) do
      raw = AdminMetricsParser.parse("")
      raw = Map.put(raw, "uptime_ms", ms)
      AdminMetrics.from_raw_metrics(raw).application.uptime_human
    end

    test "seconds only (< 60s)" do
      assert uptime_human(30_000) == "30s"
    end

    test "minutes only (< 1h)" do
      assert uptime_human(90_000) == "1m"
      assert uptime_human(3_599_000) == "59m"
    end

    test "hours and minutes (< 1d)" do
      assert uptime_human(3_600_000) == "1h 0m"
      assert uptime_human(3_661_000) == "1h 1m"
    end

    test "days, hours, and minutes (>= 1d)" do
      assert uptime_human(86_400_000) == "1d 0h 0m"
      assert uptime_human(90_061_000) == "1d 1h 1m"
    end
  end
end
