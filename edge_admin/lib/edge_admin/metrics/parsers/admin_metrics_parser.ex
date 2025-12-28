# edge_admin/lib/edge_admin/metrics/parsers/admin_metrics_parser.ex
defmodule EdgeAdmin.Metrics.Parsers.AdminMetricsParser do
  @moduledoc """
  Parses Prometheus text format from admin PromEx endpoint.

  Extracts business metrics (metadata, bootstrap, nodes) and
  application health metrics (BEAM stats, Oban queues).
  """

  @doc """
  Parses raw Prometheus metrics text from admin PromEx.

  Returns a map with parsed metric values.
  """
  def parse(metrics_text) do
    lines = String.split(metrics_text, "\n")

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

      # Bootstrap
      "bootstrap_steps" => extract_counter(lines, "edge_admin_bootstrap_step_total"),

      # Nodes health checks
      "nodes_health_checks" => extract_counter(lines, "edge_admin_nodes_health_check_total"),

      # Quantum scheduler jobs
      "quantum_jobs_executed" => extract_counter(lines, "edge_admin_quantum_job_executed_total"),
      "quantum_jobs_exceptions" => extract_counter(lines, "edge_admin_quantum_job_exception_total"),

      # VPN zombie admin cleanup
      "vpn_zombie_cleanup_total" => extract_counter(lines, "edge_admin_vpn_zombie_admin_cleanup_total"),
      "vpn_zombie_cleanup_deleted_count" => extract_gauge(lines, "edge_admin_vpn_zombie_admin_cleanup_deleted_count"),

      # Commands execution delivery
      "commands_delivery_total" => extract_counter(lines, "edge_admin_commands_delivery_total"),
      "commands_delivery_delivered_count" => extract_gauge(lines, "edge_admin_commands_delivery_delivered_count"),

      # Gateway
      "gateway_connections_total" => extract_counter(lines, "edge_admin_gateway_connection_total"),
      "gateway_active_count" => extract_gauge(lines, "edge_admin_gateway_active_count"),
      "gateway_scrapes_total" => extract_counter(lines, "edge_admin_gateway_scrape_total"),

      # Oban queues
      "oban_queues" => extract_oban_queues(lines)
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
