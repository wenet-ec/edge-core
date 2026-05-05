# edge_admin/lib/edge_admin/prom_ex/edge_admin_plugin.ex
defmodule EdgeAdmin.PromEx.EdgeAdminPlugin do
  @moduledoc """
  Custom PromEx plugin for edge_admin specific metrics.

  Provides business-level metrics for:
  - Membership process (admin-cluster join)
  - Discovery operations (finding other admins)
  - Metadata recomputation (cluster assignments)
  - Proxy server (HTTP/SOCKS5)
  - Node health checks
  - Command execution and delivery
  - Quantum scheduler jobs
  - VPN zombie admin cleanup
  - Gateway connections and metrics scraping
  - SSH credential verification
  - Cluster reconciliation (Oban worker)
  - Self-update request processing
  - Event broker publishing (opt-in — zero events when disabled)
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :edge_admin_event_metrics,
      membership_metrics() ++
        discovery_metrics() ++
        metadata_metrics() ++
        proxy_metrics() ++
        node_health_metrics() ++
        command_metrics() ++
        quantum_metrics() ++
        worker_result_metrics() ++
        gateway_metrics() ++
        ssh_metrics() ++
        reconciliation_metrics() ++
        self_update_metrics() ++
        event_broker_metrics() ++
        webhook_metrics()
    )
  end

  defp membership_metrics do
    [
      counter(
        [:edge_admin, :membership, :step, :total],
        event_name: [:edge_admin, :membership, :step],
        description: "Total number of membership steps executed",
        tags: [:step, :status],
        tag_values: &get_membership_step_tags/1
      ),
      distribution(
        [:edge_admin, :membership, :step, :duration, :milliseconds],
        event_name: [:edge_admin, :membership, :step],
        description: "Duration of individual membership steps in milliseconds",
        measurement: :duration,
        tags: [:step, :status],
        tag_values: &get_membership_step_tags/1,
        reporter_options: [buckets: [100, 500, 1_000, 2_000, 5_000, 10_000, 30_000]]
      ),
      counter(
        [:edge_admin, :membership, :complete, :total],
        event_name: [:edge_admin, :membership, :complete],
        description: "Total number of completed membership sequences",
        tags: [:status],
        tag_values: &get_status_tag/1
      ),
      distribution(
        [:edge_admin, :membership, :complete, :duration, :milliseconds],
        event_name: [:edge_admin, :membership, :complete],
        description: "Total duration of the full membership sequence in milliseconds",
        measurement: :duration,
        tags: [:status],
        tag_values: &get_status_tag/1,
        reporter_options: [buckets: [500, 1_000, 2_000, 5_000, 10_000, 30_000, 60_000]]
      )
    ]
  end

  defp discovery_metrics do
    [
      counter(
        [:edge_admin, :discovery, :scan_complete, :total],
        event_name: [:edge_admin, :discovery, :scan_complete],
        description: "Total number of peer discovery scans completed"
      ),
      counter(
        [:edge_admin, :discovery, :dns_resolution, :total],
        event_name: [:edge_admin, :discovery, :dns_resolution],
        description: "Total DNS resolution attempts during peer discovery",
        tags: [:result],
        tag_values: &get_result_tag/1
      ),
      counter(
        [:edge_admin, :discovery, :peer_connection, :total],
        event_name: [:edge_admin, :discovery, :peer_connection],
        description: "Total Erlang peer connection attempts",
        tags: [:result],
        tag_values: &get_result_tag/1
      )
    ]
  end

  defp metadata_metrics do
    [
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
        reporter_options: [buckets: [10, 50, 100, 500, 1_000, 5_000, 10_000]]
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
      )
    ]
  end

  defp proxy_metrics do
    [
      counter(
        [:edge_admin, :proxy, :connection, :total],
        event_name: [:edge_admin, :proxy, :connection],
        description: "Total proxy connections by protocol, result, routing mode, proxy mode, and cluster",
        tags: [:protocol, :result, :routing_mode, :proxy_mode, :cluster],
        tag_values: &get_proxy_connection_tags/1
      ),
      counter(
        [:edge_admin, :proxy, :auth_failure, :total],
        event_name: [:edge_admin, :proxy, :auth_failure],
        description: "Total proxy authentication failures by protocol",
        tags: [:protocol],
        tag_values: &get_protocol_tag/1
      ),
      distribution(
        [:edge_admin, :proxy, :session, :duration, :milliseconds],
        event_name: [:edge_admin, :proxy, :session, :duration],
        description:
          "Proxy session duration in milliseconds, tagged by protocol, routing mode (local/remote), proxy mode (direct/chain), and cluster",
        measurement: :duration,
        tags: [:protocol, :routing_mode, :proxy_mode, :cluster],
        tag_values: &get_proxy_session_tags/1,
        reporter_options: [
          buckets: [100, 500, 1_000, 5_000, 15_000, 30_000, 60_000, 300_000, 900_000]
        ]
      ),
      counter(
        [:edge_admin, :proxy, :tunnel, :closed, :total],
        event_name: [:edge_admin, :proxy, :tunnel, :closed],
        description:
          "Tunnels that finished forwarding, tagged by protocol, routing mode, cluster, and close reason (normal | deadline | drain_timeout)",
        tags: [:protocol, :routing_mode, :cluster, :reason],
        tag_values: &get_proxy_tunnel_close_tags/1
      ),
      sum(
        [:edge_admin, :proxy, :tunnel, :bytes, :up, :total],
        event_name: [:edge_admin, :proxy, :tunnel, :closed],
        description: "Cumulative bytes forwarded client→target, tagged by protocol, routing mode, cluster",
        measurement: :bytes_up,
        tags: [:protocol, :routing_mode, :cluster],
        tag_values: &get_proxy_tunnel_bytes_tags/1
      ),
      sum(
        [:edge_admin, :proxy, :tunnel, :bytes, :down, :total],
        event_name: [:edge_admin, :proxy, :tunnel, :closed],
        description: "Cumulative bytes forwarded target→client, tagged by protocol, routing mode, cluster",
        measurement: :bytes_down,
        tags: [:protocol, :routing_mode, :cluster],
        tag_values: &get_proxy_tunnel_bytes_tags/1
      ),
      distribution(
        [:edge_admin, :proxy, :tunnel, :duration, :milliseconds],
        event_name: [:edge_admin, :proxy, :tunnel, :closed],
        description: "Tunnel forwarding duration in milliseconds, tagged by protocol, routing mode, cluster",
        measurement: :duration_ms,
        tags: [:protocol, :routing_mode, :cluster],
        tag_values: &get_proxy_tunnel_bytes_tags/1,
        reporter_options: [
          buckets: [100, 500, 1_000, 5_000, 15_000, 60_000, 300_000, 900_000, 3_600_000]
        ]
      )
    ]
  end

  defp node_health_metrics do
    [
      counter(
        [:edge_admin, :nodes, :health_check, :total],
        event_name: [:edge_admin, :nodes, :health_check],
        description: "Total number of individual node health checks",
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
        reporter_options: [buckets: [10, 50, 100, 500, 1_000, 5_000]]
      ),
      last_value(
        [:edge_admin, :nodes, :health_check_summary, :unhealthy_count],
        event_name: [:edge_admin, :nodes, :health_check_summary],
        description: "Number of unhealthy/unreachable nodes in last health check run",
        measurement: :unhealthy_count
      )
    ]
  end

  defp command_metrics do
    [
      counter(
        [:edge_admin, :commands, :execution, :created, :total],
        event_name: [:edge_admin, :commands, :execution, :created],
        description: "Total number of command executions created",
        tags: [:targeting_type],
        tag_values: &get_targeting_type_tag/1
      ),
      counter(
        [:edge_admin, :commands, :execution, :delivered, :total],
        event_name: [:edge_admin, :commands, :execution, :delivered],
        description: "Total number of individual execution delivery attempts to agents",
        tags: [:result],
        tag_values: &get_result_tag/1
      ),
      counter(
        [:edge_admin, :commands, :execution, :completed, :total],
        event_name: [:edge_admin, :commands, :execution, :completed],
        description: "Total number of command executions completed (result reported back by agent)",
        tags: [:exit_code_category],
        tag_values: &get_exit_code_category_tag/1
      ),
      distribution(
        [:edge_admin, :commands, :execution, :completed, :duration, :milliseconds],
        event_name: [:edge_admin, :commands, :execution, :completed],
        description: "End-to-end duration of command executions in milliseconds (sent_at to result received)",
        measurement: :duration,
        tags: [:exit_code_category],
        tag_values: &get_exit_code_category_tag/1,
        reporter_options: [buckets: [100, 500, 1_000, 5_000, 10_000, 30_000, 60_000]]
      ),
      counter(
        [:edge_admin, :commands, :expiration, :total],
        event_name: [:edge_admin, :commands, :expiration],
        description: "Total number of stale execution expiration runs"
      ),
      last_value(
        [:edge_admin, :commands, :expiration, :expired_count],
        event_name: [:edge_admin, :commands, :expiration],
        description: "Number of executions expired in last expiration run",
        measurement: :expired_count
      ),
      counter(
        [:edge_admin, :commands, :pruning, :total],
        event_name: [:edge_admin, :commands, :pruning],
        description: "Total number of execution pruning runs (delete old finalised rows)"
      ),
      last_value(
        [:edge_admin, :commands, :pruning, :deleted_count],
        event_name: [:edge_admin, :commands, :pruning],
        description: "Number of executions deleted in last pruning run",
        measurement: :deleted_count
      ),
      distribution(
        [:edge_admin, :commands, :pruning, :duration, :milliseconds],
        event_name: [:edge_admin, :commands, :pruning],
        description: "Duration of execution pruning runs in milliseconds",
        measurement: :duration,
        reporter_options: [buckets: [10, 100, 500, 1_000, 5_000, 30_000, 60_000, 300_000]]
      )
    ]
  end

  defp quantum_metrics do
    [
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
        reporter_options: [buckets: [10, 50, 100, 500, 1_000, 5_000, 10_000, 30_000]]
      ),
      counter(
        [:edge_admin, :quantum, :job, :exception, :total],
        event_name: [:quantum, :job, :exception],
        description: "Total number of Quantum job exceptions",
        tags: [:job_name, :kind],
        tag_values: &get_quantum_exception_tags/1
      )
    ]
  end

  defp worker_result_metrics do
    [
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
        description: "Total execution delivery batch runs",
        tags: [:result],
        tag_values: &get_result_tag/1
      ),
      last_value(
        [:edge_admin, :commands, :delivery, :delivered_count],
        event_name: [:edge_admin, :commands, :delivery],
        description: "Number of executions queued for delivery in last batch run",
        measurement: :delivered_count
      )
    ]
  end

  defp gateway_metrics do
    [
      counter(
        [:edge_admin, :gateway, :connection, :total],
        event_name: [:edge_admin, :gateway, :connection],
        description: "Total gateway connection events (connected/disconnected per cluster)",
        tags: [:cluster, :event],
        tag_values: &get_gateway_tags/1
      ),
      last_value(
        [:edge_admin, :gateway, :active_count],
        event_name: [:edge_admin, :gateway, :active_count],
        description: "Current number of active gateway connections on this admin",
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
  end

  defp ssh_metrics do
    [
      counter(
        [:edge_admin, :ssh, :verification, :total],
        event_name: [:edge_admin, :ssh, :verification],
        description: "Total SSH credential verification attempts",
        tags: [:result, :auth_method],
        tag_values: &get_ssh_verification_tags/1
      )
    ]
  end

  defp reconciliation_metrics do
    [
      counter(
        [:edge_admin, :nodes, :cluster_reconciliation, :total],
        event_name: [:edge_admin, :nodes, :cluster_reconciliation],
        description: "Total cluster reconciliation runs",
        tags: [:cluster, :result],
        tag_values: &get_reconciliation_tags/1
      ),
      distribution(
        [:edge_admin, :nodes, :cluster_reconciliation, :duration, :milliseconds],
        event_name: [:edge_admin, :nodes, :cluster_reconciliation],
        description: "Duration of cluster reconciliation runs in milliseconds",
        measurement: :duration,
        tags: [:cluster, :result],
        tag_values: &get_reconciliation_tags/1,
        reporter_options: [buckets: [100, 500, 1_000, 5_000, 10_000, 30_000, 60_000]]
      ),
      last_value(
        [:edge_admin, :nodes, :cluster_reconciliation, :nodes_added],
        event_name: [:edge_admin, :nodes, :cluster_reconciliation],
        description: "Nodes added to Netmaker in last reconciliation run",
        measurement: :nodes_added
      ),
      last_value(
        [:edge_admin, :nodes, :cluster_reconciliation, :nodes_removed],
        event_name: [:edge_admin, :nodes, :cluster_reconciliation],
        description: "Nodes removed from Netmaker in last reconciliation run",
        measurement: :nodes_removed
      ),
      last_value(
        [:edge_admin, :nodes, :cluster_reconciliation, :nodes_deleted],
        event_name: [:edge_admin, :nodes, :cluster_reconciliation],
        description: "Orphaned DB node records deleted in last reconciliation run",
        measurement: :nodes_deleted
      ),
      last_value(
        [:edge_admin, :nodes, :cluster_reconciliation, :errors],
        event_name: [:edge_admin, :nodes, :cluster_reconciliation],
        description: "Number of errors in last reconciliation run",
        measurement: :errors
      )
    ]
  end

  defp self_update_metrics do
    [
      counter(
        [:edge_admin, :self_updates, :request_completed, :total],
        event_name: [:edge_admin, :self_updates, :request_completed],
        description: "Total self-update requests processed",
        tags: [:targeting_type],
        tag_values: &get_targeting_type_tag/1
      ),
      last_value(
        [:edge_admin, :self_updates, :request_completed, :triggered],
        event_name: [:edge_admin, :self_updates, :request_completed],
        description: "Nodes successfully triggered in last self-update request",
        measurement: :triggered
      ),
      last_value(
        [:edge_admin, :self_updates, :request_completed, :failed],
        event_name: [:edge_admin, :self_updates, :request_completed],
        description: "Nodes that failed to trigger in last self-update request",
        measurement: :failed
      )
    ]
  end

  defp event_broker_metrics do
    [
      counter(
        [:edge_admin, :event_broker, :enqueue, :total],
        event_name: [:edge_admin, :event_broker, :enqueue],
        description: "Total events enqueued for async broker delivery (before broker publish attempt)",
        tags: [:event_type],
        tag_values: &get_event_broker_enqueue_tags/1
      ),
      counter(
        [:edge_admin, :event_broker, :publish, :total],
        event_name: [:edge_admin, :event_broker, :publish],
        description: "Total broker publish attempts, tagged by adapter, event type, and result (ok | error)",
        tags: [:adapter, :event_type, :result],
        tag_values: &get_event_broker_publish_tags/1
      ),
      distribution(
        [:edge_admin, :event_broker, :publish, :duration, :milliseconds],
        event_name: [:edge_admin, :event_broker, :publish],
        description: "Duration of broker publish attempts in milliseconds, tagged by adapter and event type",
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:adapter, :event_type],
        tag_values: &get_event_broker_publish_duration_tags/1,
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1_000, 5_000]]
      )
    ]
  end

  defp webhook_metrics do
    [
      counter(
        [:edge_admin, :webhook, :fan_out, :total],
        event_name: [:edge_admin, :webhook, :fan_out],
        description:
          "Total fan-out invocations per published event. `count` measurement is the number of matching webhooks.",
        measurement: :count,
        tags: [:event_type],
        tag_values: &get_webhook_fan_out_tags/1
      ),
      counter(
        [:edge_admin, :webhook, :delivery, :total],
        event_name: [:edge_admin, :webhook, :delivery],
        description:
          "Total webhook delivery attempts, tagged by event type, webhook id, and result (ok | recoverable | terminal)",
        tags: [:event_type, :webhook_id, :result],
        tag_values: &get_webhook_delivery_tags/1
      ),
      distribution(
        [:edge_admin, :webhook, :delivery, :duration, :milliseconds],
        event_name: [:edge_admin, :webhook, :delivery],
        description: "Duration of webhook delivery attempts in milliseconds, tagged by event type and webhook id",
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:event_type, :webhook_id],
        tag_values: &get_webhook_delivery_duration_tags/1,
        reporter_options: [buckets: [25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 30_000]]
      )
    ]
  end

  # Tag extraction functions

  defp get_membership_step_tags(%{step: step, status: status}) do
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

  defp get_exit_code_category_tag(%{exit_code_category: exit_code_category}) do
    %{exit_code_category: to_string(exit_code_category)}
  end

  defp get_quantum_job_tags(metadata) do
    job_name = metadata[:job] |> Map.get(:name) |> to_string()
    result = if match?({:ok, _}, metadata[:result]), do: "success", else: "error"
    %{job_name: job_name, result: result}
  end

  defp get_quantum_exception_tags(metadata) do
    job_name = metadata[:job] |> Map.get(:name) |> to_string()
    kind = to_string(metadata[:kind])
    %{job_name: job_name, kind: kind}
  end

  defp get_gateway_tags(%{cluster: cluster, event: event}) do
    %{cluster: to_string(cluster), event: to_string(event)}
  end

  defp get_gateway_scrape_tags(%{cluster: cluster, metrics_type: metrics_type, result: result}) do
    %{cluster: to_string(cluster), metrics_type: to_string(metrics_type), result: to_string(result)}
  end

  defp get_proxy_connection_tags(%{
         protocol: protocol,
         result: result,
         routing_mode: routing_mode,
         proxy_mode: proxy_mode,
         cluster: cluster
       }) do
    %{
      protocol: to_string(protocol),
      result: to_string(result),
      routing_mode: to_string(routing_mode),
      proxy_mode: to_string(proxy_mode),
      cluster: to_string(cluster)
    }
  end

  defp get_proxy_session_tags(%{
         protocol: protocol,
         routing_mode: routing_mode,
         proxy_mode: proxy_mode,
         cluster: cluster
       }) do
    %{
      protocol: to_string(protocol),
      routing_mode: to_string(routing_mode),
      proxy_mode: to_string(proxy_mode),
      cluster: to_string(cluster)
    }
  end

  # Tunnel-close counter: includes :reason (normal | deadline | drain_timeout) for
  # alerting on abnormal closes. target_host intentionally excluded — too high
  # cardinality for Prometheus labels, still available in the raw telemetry event.
  defp get_proxy_tunnel_close_tags(metadata) do
    %{
      protocol: to_string(Map.get(metadata, :protocol, "unknown")),
      routing_mode: to_string(Map.get(metadata, :routing_mode, "unknown")),
      cluster: to_string(Map.get(metadata, :cluster, "unknown")),
      reason: to_string(Map.get(metadata, :reason, :normal))
    }
  end

  # Bytes/duration metrics: no :reason tag (lower cardinality, and "how much
  # did we move" isn't conditional on how the tunnel ended).
  defp get_proxy_tunnel_bytes_tags(metadata) do
    %{
      protocol: to_string(Map.get(metadata, :protocol, "unknown")),
      routing_mode: to_string(Map.get(metadata, :routing_mode, "unknown")),
      cluster: to_string(Map.get(metadata, :cluster, "unknown"))
    }
  end

  defp get_protocol_tag(%{protocol: protocol}) do
    %{protocol: to_string(protocol)}
  end

  defp get_ssh_verification_tags(%{result: result, auth_method: auth_method}) do
    %{result: to_string(result), auth_method: to_string(auth_method)}
  end

  defp get_reconciliation_tags(%{cluster: cluster, result: result}) do
    %{cluster: to_string(cluster), result: to_string(result)}
  end

  defp get_event_broker_enqueue_tags(%{event_type: event_type}) do
    %{event_type: to_string(event_type)}
  end

  defp get_event_broker_publish_tags(%{adapter: adapter, event_type: event_type, result: result}) do
    %{
      adapter: to_string(adapter),
      event_type: to_string(event_type),
      result: to_string(result)
    }
  end

  defp get_event_broker_publish_duration_tags(%{adapter: adapter, event_type: event_type}) do
    %{adapter: to_string(adapter), event_type: to_string(event_type)}
  end

  defp get_webhook_fan_out_tags(%{event_type: event_type}) do
    %{event_type: to_string(event_type)}
  end

  defp get_webhook_delivery_tags(%{event_type: event_type, webhook_id: webhook_id, result: result}) do
    %{
      event_type: to_string(event_type),
      webhook_id: to_string(webhook_id),
      result: to_string(result)
    }
  end

  defp get_webhook_delivery_duration_tags(%{event_type: event_type, webhook_id: webhook_id}) do
    %{event_type: to_string(event_type), webhook_id: to_string(webhook_id)}
  end
end
