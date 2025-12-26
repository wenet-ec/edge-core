# edge_admin/lib/edge_admin/prom_ex/edge_admin_plugin.ex
defmodule EdgeAdmin.PromEx.EdgeAdminPlugin do
  @moduledoc """
  Custom PromEx plugin for edge_admin specific metrics.

  Provides business-level metrics for:
  - Bootstrap process (admin initialization)
  - Discovery operations (finding other admins)
  - Metadata recomputation (cluster assignments)
  - Proxy server (HTTP/SOCKS5)
  - Node health checks
  - Command execution
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :edge_admin_event_metrics,
      [
        # Bootstrap metrics
        counter(
          [:edge_admin, :bootstrap, :step, :total],
          event_name: [:edge_admin, :bootstrap, :step],
          description: "Total number of bootstrap steps executed",
          tags: [:step, :status],
          tag_values: &get_bootstrap_tags/1
        ),
        distribution(
          [:edge_admin, :bootstrap, :step, :duration, :milliseconds],
          event_name: [:edge_admin, :bootstrap, :step],
          description: "Duration of bootstrap steps in milliseconds",
          measurement: :duration,
          tags: [:step, :status],
          tag_values: &get_bootstrap_tags/1,
          reporter_options: [
            buckets: [100, 500, 1_000, 2_000, 5_000, 10_000, 30_000]
          ]
        ),

        # Discovery metrics
        counter(
          [:edge_admin, :discovery, :scan, :total],
          event_name: [:edge_admin, :discovery, :scan],
          description: "Total number of discovery scans",
          tags: [:status],
          tag_values: &get_status_tag/1
        ),
        counter(
          [:edge_admin, :discovery, :admin, :found, :total],
          event_name: [:edge_admin, :discovery, :admin, :found],
          description: "Total number of admins found during discovery",
          tags: [:status],
          tag_values: &get_status_tag/1
        ),
        last_value(
          [:edge_admin, :discovery, :admin_cluster, :size],
          event_name: [:edge_admin, :discovery, :admin_cluster, :size],
          description: "Current size of the admin cluster",
          measurement: :size
        ),

        # Metadata recomputation metrics
        counter(
          [:edge_admin, :metadata, :recomputation, :total],
          event_name: [:edge_admin, :metadata, :recomputation],
          description: "Total number of metadata recomputations",
          tags: [:trigger],
          tag_values: &get_trigger_tag/1
        ),
        distribution(
          [:edge_admin, :metadata, :recomputation, :duration, :milliseconds],
          event_name: [:edge_admin, :metadata, :recomputation],
          description: "Duration of metadata recomputation in milliseconds",
          measurement: :duration,
          tags: [:trigger],
          tag_values: &get_trigger_tag/1,
          reporter_options: [
            buckets: [10, 50, 100, 500, 1_000, 5_000, 10_000]
          ]
        ),
        last_value(
          [:edge_admin, :metadata, :assigned_clusters],
          event_name: [:edge_admin, :metadata, :recomputation],
          description: "Number of clusters assigned to this admin",
          measurement: :assigned_clusters
        ),
        last_value(
          [:edge_admin, :metadata, :orphaned_clusters],
          event_name: [:edge_admin, :metadata, :recomputation],
          description: "Number of orphaned clusters detected",
          measurement: :orphaned_clusters
        ),
        last_value(
          [:edge_admin, :metadata, :degraded],
          event_name: [:edge_admin, :metadata, :recomputation],
          description: "Whether admin is in degraded state (0=healthy, 1=degraded)",
          measurement: :degraded
        ),

        # Proxy server metrics
        counter(
          [:edge_admin, :proxy, :http, :connection, :total],
          event_name: [:edge_admin, :proxy, :http, :connection],
          description: "Total HTTP proxy connections",
          tags: [:result],
          tag_values: &get_result_tag/1
        ),
        counter(
          [:edge_admin, :proxy, :socks5, :connection, :total],
          event_name: [:edge_admin, :proxy, :socks5, :connection],
          description: "Total SOCKS5 proxy connections",
          tags: [:result],
          tag_values: &get_result_tag/1
        ),
        last_value(
          [:edge_admin, :proxy, :active_connections],
          event_name: [:edge_admin, :proxy, :active_connections],
          description: "Current number of active proxy connections",
          measurement: :active_connections
        ),

        # Node health check metrics
        counter(
          [:edge_admin, :nodes, :health_check, :total],
          event_name: [:edge_admin, :nodes, :health_check],
          description: "Total number of node health checks",
          tags: [:result],
          tag_values: &get_result_tag/1
        ),
        distribution(
          [:edge_admin, :nodes, :health_check, :duration, :milliseconds],
          event_name: [:edge_admin, :nodes, :health_check],
          description: "Duration of individual node health checks in milliseconds",
          measurement: :duration,
          tags: [:result],
          tag_values: &get_result_tag/1,
          reporter_options: [
            buckets: [10, 50, 100, 500, 1_000, 5_000]
          ]
        ),
        last_value(
          [:edge_admin, :nodes, :health_check, :summary, :total_nodes],
          event_name: [:edge_admin, :nodes, :health_check, :summary],
          description: "Total number of nodes checked in last health check run",
          measurement: :total_nodes
        ),

        # Command execution metrics
        counter(
          [:edge_admin, :commands, :created, :total],
          event_name: [:edge_admin, :commands, :created],
          description: "Total number of commands created"
        ),
        counter(
          [:edge_admin, :commands, :execution, :created, :total],
          event_name: [:edge_admin, :commands, :execution, :created],
          description: "Total number of command executions created",
          tags: [:targeting_type],
          tag_values: &get_targeting_type_tag/1
        ),
        counter(
          [:edge_admin, :commands, :execution, :status_updated, :total],
          event_name: [:edge_admin, :commands, :execution, :status_updated],
          description: "Total number of command execution status updates",
          tags: [:status],
          tag_values: &get_status_tag/1
        ),
        distribution(
          [:edge_admin, :commands, :execution, :duration, :milliseconds],
          event_name: [:edge_admin, :commands, :execution, :duration],
          description: "Duration of command executions in milliseconds",
          measurement: :duration,
          tags: [:status],
          tag_values: &get_status_tag/1,
          reporter_options: [
            buckets: [100, 500, 1_000, 5_000, 10_000, 30_000, 60_000]
          ]
        ),

        # Quantum scheduler job metrics (leveraging Quantum's built-in telemetry)
        counter(
          [:edge_admin, :quantum, :job, :executed, :total],
          event_name: [:quantum, :job, :stop],
          description: "Total number of Quantum jobs executed",
          tags: [:job_name, :result],
          tag_values: &get_quantum_job_tags/1
        ),
        distribution(
          [:edge_admin, :quantum, :job, :duration, :milliseconds],
          event_name: [:quantum, :job, :stop],
          description: "Duration of Quantum job executions in native time units",
          measurement: :duration,
          unit: {:native, :millisecond},
          tags: [:job_name, :result],
          tag_values: &get_quantum_job_tags/1,
          reporter_options: [
            buckets: [10, 50, 100, 500, 1_000, 5_000, 10_000, 30_000]
          ]
        ),
        counter(
          [:edge_admin, :quantum, :job, :exception, :total],
          event_name: [:quantum, :job, :exception],
          description: "Total number of Quantum job exceptions",
          tags: [:job_name, :kind],
          tag_values: &get_quantum_exception_tags/1
        ),

        # Oban worker result metrics
        counter(
          [:edge_admin, :vpn, :zombie_admin_cleanup, :total],
          event_name: [:edge_admin, :vpn, :zombie_admin_cleanup],
          description: "Total zombie admin cleanup runs",
          tags: [:result],
          tag_values: &get_result_tag/1
        ),
        last_value(
          [:edge_admin, :vpn, :zombie_admin_cleanup, :deleted_count],
          event_name: [:edge_admin, :vpn, :zombie_admin_cleanup],
          description: "Number of zombie admins deleted in last cleanup",
          measurement: :deleted_count
        ),

        counter(
          [:edge_admin, :commands, :delivery, :total],
          event_name: [:edge_admin, :commands, :delivery],
          description: "Total execution delivery runs",
          tags: [:result],
          tag_values: &get_result_tag/1
        ),
        last_value(
          [:edge_admin, :commands, :delivery, :delivered_count],
          event_name: [:edge_admin, :commands, :delivery],
          description: "Number of executions delivered in last run",
          measurement: :delivered_count
        ),

        # Gateway metrics
        counter(
          [:edge_admin, :gateway, :connection, :total],
          event_name: [:edge_admin, :gateway, :connection],
          description: "Total gateway connection events",
          tags: [:cluster, :event],
          tag_values: &get_gateway_tags/1
        ),
        last_value(
          [:edge_admin, :gateway, :active_count],
          event_name: [:edge_admin, :gateway, :active_count],
          description: "Current number of active gateway connections",
          measurement: :active_count
        ),
        counter(
          [:edge_admin, :gateway, :scrape, :total],
          event_name: [:edge_admin, :gateway, :scrape],
          description: "Total gateway metrics scrape operations",
          tags: [:cluster, :metrics_type, :result],
          tag_values: &get_gateway_scrape_tags/1
        )
      ]
    )
  end

  # Tag extraction functions
  defp get_bootstrap_tags(%{step: step, status: status}) do
    %{step: to_string(step), status: to_string(status)}
  end

  defp get_status_tag(%{status: status}) do
    %{status: to_string(status)}
  end

  defp get_trigger_tag(%{trigger: trigger}) do
    %{trigger: to_string(trigger)}
  end

  defp get_result_tag(%{result: result}) do
    %{result: to_string(result)}
  end

  defp get_targeting_type_tag(%{targeting_type: targeting_type}) do
    %{targeting_type: to_string(targeting_type)}
  end

  defp get_quantum_job_tags(metadata) do
    job_name = metadata[:job] |> Map.get(:name) |> to_string()
    result = if match?({:ok, _}, metadata[:result]), do: "success", else: "error"
    %{job_name: job_name, result: result}
  end

  defp get_quantum_exception_tags(metadata) do
    job_name = metadata[:job] |> Map.get(:name) |> to_string()
    kind = metadata[:kind] |> to_string()
    %{job_name: job_name, kind: kind}
  end

  defp get_gateway_tags(%{cluster: cluster, event: event}) do
    %{cluster: to_string(cluster), event: to_string(event)}
  end

  defp get_gateway_scrape_tags(%{cluster: cluster, metrics_type: metrics_type, result: result}) do
    %{cluster: to_string(cluster), metrics_type: to_string(metrics_type), result: to_string(result)}
  end
end
