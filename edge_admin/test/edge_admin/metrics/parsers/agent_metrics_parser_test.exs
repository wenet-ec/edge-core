# edge_admin/test/edge_admin/metrics/parsers/agent_metrics_parser_test.exs
defmodule EdgeAdmin.Metrics.Parsers.AgentMetricsParserTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Metrics.Parsers.AgentMetricsParser
  alias EdgeAdmin.Metrics.Schemas.AgentMetrics

  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------

  defp sample_prometheus_text do
    """
    edge_agent_prom_ex_application_uptime_milliseconds_count 60000
    edge_agent_prom_ex_beam_stats_process_count 256
    edge_agent_prom_ex_beam_memory_allocated_bytes 52428800
    edge_agent_prom_ex_beam_memory_processes_total_bytes 26214400
    edge_agent_prom_ex_beam_memory_ets_total_bytes 5242880
    edge_agent_prom_ex_beam_memory_binary_total_bytes 2097152
    edge_agent_bootstrap_registration_total{result="ok"} 1
    edge_agent_discovery_scan_total{result="ok"} 5
    edge_agent_discovery_scan_total{result="no_admins"} 2
    edge_agent_discovery_admins_found 3
    edge_agent_commands_sync_total{result="ok"} 10
    edge_agent_commands_execution_enqueued_total{result="ok"} 8
    edge_agent_commands_execution_completed_total{result="ok"} 7
    edge_agent_commands_report_total{result="ok"} 7
    edge_agent_proxy_http_connection_total{result="ok"} 100
    edge_agent_proxy_socks5_connection_total{result="ok"} 50
    edge_agent_proxy_http_blocked_total{reason="localhost_blocked"} 5
    edge_agent_proxy_http_blocked_total{reason="docker_network_blocked"} 3
    edge_agent_proxy_socks5_blocked_total{reason="localhost_blocked"} 2
    edge_agent_ssh_authentication_total{result="ok"} 4
    edge_agent_ssh_authentication_total{result="failed"} 1
    edge_agent_ssh_connection_total{result="ok"} 3
    edge_agent_prom_ex_oban_queue_length_count{queue="commands",state="available"} 3
    edge_agent_prom_ex_oban_queue_length_count{queue="commands",state="executing"} 1
    edge_agent_prom_ex_oban_queue_length_count{queue="commands",state="completed"} 50
    edge_agent_prom_ex_oban_queue_length_count{queue="commands",state="discarded"} 0
    edge_agent_prom_ex_oban_queue_length_count{queue="commands",state="retryable"} 2
    """
  end

  defp empty_prometheus_text, do: ""

  # ---------------------------------------------------------------------------
  # parse/1 — gauge extraction
  # ---------------------------------------------------------------------------

  describe "parse/1 — gauge extraction" do
    test "extracts uptime_ms" do
      result = AgentMetricsParser.parse(sample_prometheus_text())
      assert result["uptime_ms"] == 60_000
    end

    test "extracts BEAM process count and memory" do
      result = AgentMetricsParser.parse(sample_prometheus_text())
      assert result["process_count"] == 256
      assert result["memory_total"] == 52_428_800
      assert result["memory_processes"] == 26_214_400
      assert result["memory_ets"] == 5_242_880
      assert result["memory_binary"] == 2_097_152
    end

    test "extracts admins_found gauge" do
      result = AgentMetricsParser.parse(sample_prometheus_text())
      assert result["admins_found"] == 3
    end

    test "gauge returns nil when metric not present" do
      result = AgentMetricsParser.parse(empty_prometheus_text())
      assert result["uptime_ms"] == nil
      assert result["process_count"] == nil
      assert result["admins_found"] == nil
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — counter extraction (sums across labels)
  # ---------------------------------------------------------------------------

  describe "parse/1 — counter extraction" do
    test "sums discovery_scans across result labels" do
      result = AgentMetricsParser.parse(sample_prometheus_text())
      # ok(5) + no_admins(2) = 7
      assert result["discovery_scans"] == 7
    end

    test "sums ssh_authentications across result labels" do
      result = AgentMetricsParser.parse(sample_prometheus_text())
      # ok(4) + failed(1) = 5
      assert result["ssh_authentications"] == 5
    end

    test "sums proxy_http_blocked across reason labels" do
      result = AgentMetricsParser.parse(sample_prometheus_text())
      # localhost_blocked(5) + docker_network_blocked(3) = 8
      assert result["proxy_http_blocked"] == 8
    end

    test "counter returns 0 when metric not present" do
      result = AgentMetricsParser.parse(empty_prometheus_text())
      assert result["discovery_scans"] == 0
      assert result["commands_synced"] == 0
      assert result["ssh_authentications"] == 0
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — extract_counter_by_label (blocked_by_reason)
  # ---------------------------------------------------------------------------

  describe "parse/1 — extract_counter_by_label" do
    test "http blocked_by_reason groups counts by reason label" do
      result = AgentMetricsParser.parse(sample_prometheus_text())

      assert result["proxy_http_blocked_by_reason"] == %{
               "localhost_blocked" => 5,
               "docker_network_blocked" => 3
             }
    end

    test "socks5 blocked_by_reason groups counts by reason label" do
      result = AgentMetricsParser.parse(sample_prometheus_text())

      assert result["proxy_socks5_blocked_by_reason"] == %{
               "localhost_blocked" => 2
             }
    end

    test "blocked_by_reason is empty map when no blocked metrics present" do
      result = AgentMetricsParser.parse(empty_prometheus_text())
      assert result["proxy_http_blocked_by_reason"] == %{}
      assert result["proxy_socks5_blocked_by_reason"] == %{}
    end

    test "same reason label across multiple lines is summed" do
      text = """
      edge_agent_proxy_http_blocked_total{reason="localhost_blocked",node="a"} 3
      edge_agent_proxy_http_blocked_total{reason="localhost_blocked",node="b"} 4
      """

      result = AgentMetricsParser.parse(text)
      assert result["proxy_http_blocked_by_reason"]["localhost_blocked"] == 7
    end
  end

  # ---------------------------------------------------------------------------
  # parse/1 — Oban queue extraction
  # ---------------------------------------------------------------------------

  describe "parse/1 — Oban queue extraction" do
    test "extracts queue name" do
      result = AgentMetricsParser.parse(sample_prometheus_text())
      queue_names = Enum.map(result["oban_queues"], & &1["queue"])
      assert queue_names == ["commands"]
    end

    test "extracts all states per queue under 'states' key" do
      result = AgentMetricsParser.parse(sample_prometheus_text())
      commands_queue = Enum.find(result["oban_queues"], &(&1["queue"] == "commands"))
      states = commands_queue["states"]
      assert states["available"] == 3
      assert states["executing"] == 1
      assert states["completed"] == 50
      assert states["discarded"] == 0
      assert states["retryable"] == 2
    end

    test "missing state defaults to 0" do
      text = ~s(edge_agent_prom_ex_oban_queue_length_count{queue="default",state="available"} 9\n)
      result = AgentMetricsParser.parse(text)
      queue = Enum.find(result["oban_queues"], &(&1["queue"] == "default"))
      assert queue["states"]["available"] == 9
      assert queue["states"]["executing"] == 0
    end

    test "returns empty list when no Oban metrics present" do
      result = AgentMetricsParser.parse(empty_prometheus_text())
      assert result["oban_queues"] == []
    end
  end

  # ---------------------------------------------------------------------------
  # AgentMetrics.from_raw_metrics/2 — struct assembly
  # ---------------------------------------------------------------------------

  describe "AgentMetrics.from_raw_metrics/2" do
    test "builds all top-level struct fields" do
      raw = AgentMetricsParser.parse(sample_prometheus_text())
      raw = Map.put(raw, "cluster_name", "prod")
      metrics = AgentMetrics.from_raw_metrics(raw, "node-abc")

      assert %AgentMetrics{} = metrics
      assert metrics.node_id == "node-abc"
      assert metrics.cluster_name == "prod"
      assert %AgentMetrics.Application{} = metrics.application
      assert %AgentMetrics.Commands{} = metrics.commands
      assert %AgentMetrics.Discovery{} = metrics.discovery
      assert %AgentMetrics.Proxy{} = metrics.proxy
      assert %AgentMetrics.Ssh{} = metrics.ssh
      assert is_list(metrics.oban_queues)
    end

    test "application uptime converted from ms to seconds" do
      raw = AgentMetricsParser.parse(sample_prometheus_text())
      raw = Map.put(raw, "cluster_name", "prod")
      metrics = AgentMetrics.from_raw_metrics(raw, "node-abc")
      # 60000ms / 1000 = 60s
      assert metrics.application.uptime_seconds == 60
      assert metrics.application.uptime_human == "1m"
    end

    test "application memory converted to MB" do
      raw = AgentMetricsParser.parse(sample_prometheus_text())
      raw = Map.put(raw, "cluster_name", "prod")
      metrics = AgentMetrics.from_raw_metrics(raw, "node-abc")
      # 52428800 / 1048576 = 50.0 MB
      assert metrics.application.memory_total_mb == 50.0
    end

    test "commands struct has correct totals" do
      raw = AgentMetricsParser.parse(sample_prometheus_text())
      raw = Map.put(raw, "cluster_name", "prod")
      metrics = AgentMetrics.from_raw_metrics(raw, "node-abc")
      assert metrics.commands.synced_total == 10
      assert metrics.commands.enqueued_total == 8
      assert metrics.commands.completed_total == 7
      assert metrics.commands.reported_total == 7
    end

    test "discovery struct has correct totals" do
      raw = AgentMetricsParser.parse(sample_prometheus_text())
      raw = Map.put(raw, "cluster_name", "prod")
      metrics = AgentMetrics.from_raw_metrics(raw, "node-abc")
      assert metrics.discovery.scans_total == 7
      assert metrics.discovery.admins_found_last == 3
    end

    test "proxy struct has counts and blocked_by_reason map" do
      raw = AgentMetricsParser.parse(sample_prometheus_text())
      raw = Map.put(raw, "cluster_name", "prod")
      metrics = AgentMetrics.from_raw_metrics(raw, "node-abc")
      assert metrics.proxy.http_connections_total == 100
      assert metrics.proxy.http_blocked_total == 8
      assert metrics.proxy.http_blocked_by_reason["localhost_blocked"] == 5
      assert metrics.proxy.socks5_connections_total == 50
      assert metrics.proxy.socks5_blocked_total == 2
    end

    test "ssh struct sums all authentication results" do
      raw = AgentMetricsParser.parse(sample_prometheus_text())
      raw = Map.put(raw, "cluster_name", "prod")
      metrics = AgentMetrics.from_raw_metrics(raw, "node-abc")
      assert metrics.ssh.authentications_total == 5
      assert metrics.ssh.connections_total == 3
    end

    test "oban_queues is a list of ObanQueue structs" do
      raw = AgentMetricsParser.parse(sample_prometheus_text())
      raw = Map.put(raw, "cluster_name", "prod")
      metrics = AgentMetrics.from_raw_metrics(raw, "node-abc")
      assert length(metrics.oban_queues) == 1
      assert Enum.all?(metrics.oban_queues, &match?(%AgentMetrics.ObanQueue{}, &1))
    end

    test "missing metrics default to 0 (not nil) in structs" do
      raw = AgentMetricsParser.parse(empty_prometheus_text())
      raw = Map.put(raw, "cluster_name", nil)
      metrics = AgentMetrics.from_raw_metrics(raw, "node-xyz")
      assert metrics.commands.synced_total == 0
      assert metrics.discovery.scans_total == 0
      assert metrics.proxy.http_connections_total == 0
      assert metrics.proxy.http_blocked_by_reason == %{}
      assert metrics.ssh.authentications_total == 0
    end

    test "nil uptime_ms defaults to 0 seconds" do
      raw = AgentMetricsParser.parse(empty_prometheus_text())
      raw = Map.put(raw, "cluster_name", nil)
      metrics = AgentMetrics.from_raw_metrics(raw, "node-xyz")
      assert metrics.application.uptime_seconds == 0
      assert metrics.application.uptime_human == "0s"
    end
  end
end
