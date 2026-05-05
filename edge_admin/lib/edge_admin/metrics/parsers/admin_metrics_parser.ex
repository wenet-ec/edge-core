# edge_admin/lib/edge_admin/metrics/parsers/admin_metrics_parser.ex
defmodule EdgeAdmin.Metrics.Parsers.AdminMetricsParser do
  @moduledoc """
  Parses Prometheus text format from admin PromEx endpoint.

  Extracts business metrics (metadata, membership, nodes) and
  application health metrics (BEAM stats, Oban queues).
  """

  @doc """
  Parses raw Prometheus metrics text from admin PromEx.

  Returns a map with parsed metric values.
  """
  def parse(metrics_text) do
    lines = String.split(metrics_text, "\n")

    lines
    |> extract_core_metrics()
    |> Map.merge(extract_proxy_metrics(lines))
    |> Map.merge(extract_event_broker_metrics(lines))
    |> Map.merge(extract_webhook_metrics(lines))
  end

  defp extract_core_metrics(lines) do
    %{
      # Application uptime
      "uptime_ms" => extract_gauge(lines, "edge_admin_prom_ex_application_uptime_milliseconds_count"),

      # BEAM stats
      "process_count" => extract_gauge(lines, "edge_admin_prom_ex_beam_stats_process_count"),
      "port_count" => extract_gauge(lines, "edge_admin_prom_ex_beam_stats_port_count"),
      "atom_count" => extract_gauge(lines, "edge_admin_prom_ex_beam_stats_atom_count"),
      "ets_count" => extract_gauge(lines, "edge_admin_prom_ex_beam_stats_ets_count"),
      "memory_total" => extract_gauge(lines, "edge_admin_prom_ex_beam_memory_allocated_bytes"),
      "memory_processes" => extract_gauge(lines, "edge_admin_prom_ex_beam_memory_processes_total_bytes"),
      "memory_ets" => extract_gauge(lines, "edge_admin_prom_ex_beam_memory_ets_total_bytes"),
      "memory_binary" => extract_gauge(lines, "edge_admin_prom_ex_beam_memory_binary_total_bytes"),
      "memory_code" => extract_gauge(lines, "edge_admin_prom_ex_beam_memory_code_total_bytes"),
      "memory_atom" => extract_gauge(lines, "edge_admin_prom_ex_beam_memory_atom_total_bytes"),

      # Metadata
      "metadata_degraded" => extract_gauge(lines, "edge_admin_metadata_degraded"),
      "metadata_orphaned_clusters" => extract_gauge(lines, "edge_admin_metadata_orphaned_clusters"),
      "metadata_assigned_clusters" => extract_gauge(lines, "edge_admin_metadata_assigned_clusters"),
      "metadata_recomputations" => extract_counter(lines, "edge_admin_metadata_recomputation_total"),

      # Membership
      "membership_steps" => extract_counter(lines, "edge_admin_membership_step_total"),
      "membership_complete_total" => extract_counter(lines, "edge_admin_membership_complete_total"),

      # Discovery
      "discovery_scans_total" => extract_counter(lines, "edge_admin_discovery_scan_complete_total"),
      "discovery_dns_resolutions_total" => extract_counter(lines, "edge_admin_discovery_dns_resolution_total"),
      "discovery_peer_connections_total" => extract_counter(lines, "edge_admin_discovery_peer_connection_total"),

      # Nodes health checks
      "nodes_health_checks" => extract_counter(lines, "edge_admin_nodes_health_check_total"),
      "nodes_cluster_reconciliations_total" => extract_counter(lines, "edge_admin_nodes_cluster_reconciliation_total"),
      "nodes_cluster_reconciliation_errors" => extract_gauge(lines, "edge_admin_nodes_cluster_reconciliation_errors"),

      # Quantum scheduler jobs
      "quantum_jobs_executed" => extract_counter(lines, "edge_admin_quantum_job_executed_total"),
      "quantum_jobs_exceptions" => extract_counter(lines, "edge_admin_quantum_job_exception_total"),

      # VPN zombie admin cleanup
      "vpn_zombie_cleanup_total" => extract_counter(lines, "edge_admin_vpn_zombie_admin_cleanup_total"),
      "vpn_zombie_cleanup_deleted_count" => extract_gauge(lines, "edge_admin_vpn_zombie_admin_cleanup_deleted_count"),

      # Commands
      "commands_delivery_total" => extract_counter(lines, "edge_admin_commands_delivery_total"),
      "commands_delivery_delivered_count" => extract_gauge(lines, "edge_admin_commands_delivery_delivered_count"),
      "commands_execution_delivered_total" => extract_counter(lines, "edge_admin_commands_execution_delivered_total"),
      "commands_execution_completed_total" => extract_counter(lines, "edge_admin_commands_execution_completed_total"),
      "commands_expiration_total" => extract_counter(lines, "edge_admin_commands_expiration_total"),
      "commands_pruning_total" => extract_counter(lines, "edge_admin_commands_pruning_total"),
      "commands_pruning_deleted_count" => extract_gauge(lines, "edge_admin_commands_pruning_deleted_count"),

      # SSH
      "ssh_verifications_total" => extract_counter(lines, "edge_admin_ssh_verification_total"),
      "ssh_verifications_failed" =>
        extract_counter_by_label(lines, "edge_admin_ssh_verification_total", "result", "failure"),

      # Self-updates
      "self_updates_completed_total" => extract_counter(lines, "edge_admin_self_updates_request_completed_total"),

      # Gateway
      "gateway_connections_total" => extract_counter(lines, "edge_admin_gateway_connection_total"),
      "gateway_active_count" => extract_gauge(lines, "edge_admin_gateway_active_count"),
      "gateway_scrapes_total" => extract_counter(lines, "edge_admin_gateway_scrape_total"),

      # Oban queues
      "oban_queues" => extract_oban_queues(lines)
    }
  end

  defp extract_proxy_metrics(lines) do
    %{
      # Proxy — connections
      "proxy_connections_total" => extract_counter(lines, "edge_admin_proxy_connection_total"),
      "proxy_connections_success_total" =>
        extract_counter_by_label(lines, "edge_admin_proxy_connection_total", "result", "success"),
      "proxy_connections_auth_failed_total" =>
        extract_counter_by_label(lines, "edge_admin_proxy_connection_total", "result", "auth_failed"),
      "proxy_connections_failure_total" =>
        extract_counter_by_label(lines, "edge_admin_proxy_connection_total", "result", "failure"),
      "proxy_auth_failures_total" => extract_counter(lines, "edge_admin_proxy_auth_failure_total"),

      # Proxy — tunnels
      "proxy_tunnels_closed_total" => extract_counter(lines, "edge_admin_proxy_tunnel_closed_total"),
      "proxy_tunnels_closed_normal_total" =>
        extract_counter_by_label(lines, "edge_admin_proxy_tunnel_closed_total", "reason", "normal"),
      "proxy_tunnels_closed_deadline_total" =>
        extract_counter_by_label(lines, "edge_admin_proxy_tunnel_closed_total", "reason", "deadline"),
      "proxy_tunnels_closed_drain_timeout_total" =>
        extract_counter_by_label(lines, "edge_admin_proxy_tunnel_closed_total", "reason", "drain_timeout"),
      "proxy_tunnel_bytes_up_total" => extract_counter(lines, "edge_admin_proxy_tunnel_bytes_up_total"),
      "proxy_tunnel_bytes_down_total" => extract_counter(lines, "edge_admin_proxy_tunnel_bytes_down_total")
    }
  end

  defp extract_event_broker_metrics(lines) do
    %{
      # Event broker — enqueue
      "event_broker_enqueues_total" => extract_counter(lines, "edge_admin_event_broker_enqueue_total"),

      # Event broker — publish
      "event_broker_publishes_total" => extract_counter(lines, "edge_admin_event_broker_publish_total"),
      "event_broker_publishes_ok_total" =>
        extract_counter_by_label(lines, "edge_admin_event_broker_publish_total", "result", "ok"),
      "event_broker_publishes_error_total" =>
        extract_counter_by_label(lines, "edge_admin_event_broker_publish_total", "result", "error")
    }
  end

  defp extract_webhook_metrics(lines) do
    %{
      # Webhook — fan-out (per-publish invocation count; the `count` measurement
      # itself is the webhooks-matched count, exposed as a separate _sum series
      # by Prometheus for the underlying counter).
      "webhook_fan_outs_total" => extract_counter(lines, "edge_admin_webhook_fan_out_total"),

      # Webhook — delivery
      "webhook_deliveries_total" => extract_counter(lines, "edge_admin_webhook_delivery_total"),
      "webhook_deliveries_ok_total" =>
        extract_counter_by_label(lines, "edge_admin_webhook_delivery_total", "result", "ok"),
      "webhook_deliveries_recoverable_total" =>
        extract_counter_by_label(lines, "edge_admin_webhook_delivery_total", "result", "recoverable"),
      "webhook_deliveries_terminal_total" =>
        extract_counter_by_label(lines, "edge_admin_webhook_delivery_total", "result", "terminal")
    }
  end

  # Extract simple gauge value
  defp extract_gauge(lines, metric_name) do
    lines
    |> Enum.find(fn line -> String.starts_with?(line, metric_name <> " ") end)
    |> case do
      nil ->
        nil

      line ->
        line
        |> String.split(" ")
        |> List.last()
        |> parse_number()
    end
  end

  # Extract counter total (sum across all label combinations)
  defp extract_counter(lines, metric_name) do
    lines
    |> Enum.filter(fn line ->
      String.starts_with?(line, metric_name <> "{") or String.starts_with?(line, metric_name <> " ")
    end)
    |> Enum.map(fn line ->
      line
      |> String.split(" ")
      |> List.last()
      |> parse_number()
    end)
    |> Enum.sum()
  end

  # Extract counter total filtered to lines where label_name="label_value"
  defp extract_counter_by_label(lines, metric_name, label_name, label_value) do
    pattern = ~s(#{label_name}="#{label_value}")

    lines
    |> Enum.filter(fn line ->
      String.starts_with?(line, metric_name <> "{") and String.contains?(line, pattern)
    end)
    |> Enum.map(fn line ->
      line
      |> String.split(" ")
      |> List.last()
      |> parse_number()
    end)
    |> Enum.sum()
  end

  # Parse a number string that could be an integer or float
  defp parse_number(str) do
    if String.contains?(str, ".") do
      str |> String.to_float() |> trunc()
    else
      String.to_integer(str)
    end
  end

  # Extract Oban queue counts by state
  defp extract_oban_queues(lines) do
    oban_lines =
      Enum.filter(lines, fn line ->
        String.starts_with?(line, "edge_admin_prom_ex_oban_queue_length_count{")
      end)

    queues = extract_unique_queues(oban_lines)

    Enum.map(queues, fn queue_name ->
      %{
        "queue" => queue_name,
        "available" => extract_oban_state(oban_lines, queue_name, "available"),
        "scheduled" => extract_oban_state(oban_lines, queue_name, "scheduled"),
        "executing" => extract_oban_state(oban_lines, queue_name, "executing"),
        "retryable" => extract_oban_state(oban_lines, queue_name, "retryable"),
        "completed" => extract_oban_state(oban_lines, queue_name, "completed"),
        "discarded" => extract_oban_state(oban_lines, queue_name, "discarded"),
        "cancelled" => extract_oban_state(oban_lines, queue_name, "cancelled")
      }
    end)
  end

  defp extract_unique_queues(oban_lines) do
    oban_lines
    |> Enum.map(fn line ->
      case Regex.run(~r/queue="([^"]+)"/, line) do
        [_, queue] -> queue
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp extract_oban_state(lines, queue_name, state) do
    pattern = ~s(queue="#{queue_name}",state="#{state}")

    lines
    |> Enum.find(fn line -> String.contains?(line, pattern) end)
    |> case do
      nil ->
        0

      line ->
        line
        |> String.split(" ")
        |> List.last()
        |> String.to_integer()
    end
  end
end
