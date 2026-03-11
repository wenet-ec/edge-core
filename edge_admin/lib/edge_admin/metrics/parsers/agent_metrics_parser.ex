# edge_admin/lib/edge_admin/metrics/parsers/agent_metrics_parser.ex
defmodule EdgeAdmin.Metrics.Parsers.AgentMetricsParser do
  @moduledoc """
  Parses Prometheus text format from agent PromEx endpoint.

  Extracts business metrics (commands, discovery, proxy, SSH) and
  application health metrics (BEAM stats, Oban queues).
  """

  @doc """
  Parses raw Prometheus metrics text from agent PromEx.

  Returns a map with parsed metric values.
  """
  def parse(metrics_text) do
    lines = String.split(metrics_text, "\n")

    %{
      # Application uptime
      "uptime_ms" => extract_gauge(lines, "edge_agent_prom_ex_application_uptime_milliseconds_count"),

      # BEAM stats
      "process_count" => extract_gauge(lines, "edge_agent_prom_ex_beam_stats_process_count"),
      "memory_total" => extract_gauge(lines, "edge_agent_prom_ex_beam_memory_allocated_bytes"),
      "memory_processes" => extract_gauge(lines, "edge_agent_prom_ex_beam_memory_processes_total_bytes"),
      "memory_ets" => extract_gauge(lines, "edge_agent_prom_ex_beam_memory_ets_total_bytes"),
      "memory_binary" => extract_gauge(lines, "edge_agent_prom_ex_beam_memory_binary_total_bytes"),

      # Oban queues
      "oban_queues" => extract_oban_queues(lines),

      # Bootstrap & Discovery
      "bootstrap_registrations" => extract_counter(lines, "edge_agent_bootstrap_registration_total"),
      "discovery_scans" => extract_counter(lines, "edge_agent_discovery_scan_total"),
      "admins_found" => extract_gauge(lines, "edge_agent_discovery_admins_found"),

      # Commands
      "commands_synced" => extract_counter(lines, "edge_agent_commands_sync_total"),
      "commands_enqueued" => extract_counter(lines, "edge_agent_commands_execution_enqueued_total"),
      "commands_completed" => extract_counter(lines, "edge_agent_commands_execution_completed_total"),
      "commands_reported" => extract_counter(lines, "edge_agent_commands_report_total"),

      # Proxy
      "proxy_http_connections" => extract_counter(lines, "edge_agent_proxy_http_connection_total"),
      "proxy_socks5_connections" => extract_counter(lines, "edge_agent_proxy_socks5_connection_total"),
      "proxy_http_blocked" => extract_counter(lines, "edge_agent_proxy_http_blocked_total"),
      "proxy_socks5_blocked" => extract_counter(lines, "edge_agent_proxy_socks5_blocked_total"),
      "proxy_http_blocked_by_reason" =>
        extract_counter_by_label(lines, "edge_agent_proxy_http_blocked_total", "reason"),
      "proxy_socks5_blocked_by_reason" =>
        extract_counter_by_label(lines, "edge_agent_proxy_socks5_blocked_total", "reason"),

      # SSH
      "ssh_authentications" => extract_counter(lines, "edge_agent_ssh_authentication_total"),
      "ssh_connections" => extract_counter(lines, "edge_agent_ssh_connection_total")
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

  # Extract counter values grouped by label
  # Returns a map like %{"localhost_blocked" => 5, "docker_network_blocked" => 3}
  defp extract_counter_by_label(lines, metric_name, label_name) do
    lines
    |> Enum.filter(fn line ->
      String.starts_with?(line, metric_name <> "{")
    end)
    |> Enum.reduce(%{}, fn line, acc ->
      case Regex.run(~r/#{label_name}="([^"]+)"/, line) do
        [_, label_value] ->
          value =
            line
            |> String.split(" ")
            |> List.last()
            |> parse_number()

          Map.update(acc, label_value, value, &(&1 + value))

        _ ->
          acc
      end
    end)
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
        String.starts_with?(line, "edge_agent_prom_ex_oban_queue_length_count{")
      end)

    queues = extract_unique_queues(oban_lines)

    Enum.map(queues, fn queue_name ->
      states = %{
        "available" => extract_oban_state(oban_lines, queue_name, "available"),
        "executing" => extract_oban_state(oban_lines, queue_name, "executing"),
        "completed" => extract_oban_state(oban_lines, queue_name, "completed"),
        "discarded" => extract_oban_state(oban_lines, queue_name, "discarded"),
        "retryable" => extract_oban_state(oban_lines, queue_name, "retryable")
      }

      %{
        "queue" => queue_name,
        "states" => states
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
