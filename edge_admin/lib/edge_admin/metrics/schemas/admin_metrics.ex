# edge_admin/lib/edge_admin/metrics/schemas/admin_metrics.ex
defmodule EdgeAdmin.Metrics.Schemas.AdminMetrics do
  @moduledoc """
  Schema for human-friendly admin application metrics.
  """

  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.Application
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

  @type t :: %__MODULE__{}

  @derive JSON.Encoder
  defstruct [
    :timestamp,
    :application,
    :metadata,
    :membership,
    :discovery,
    :nodes,
    :quantum,
    :vpn,
    :commands,
    :ssh,
    :reconciliation,
    :self_updates,
    :gateways,
    :proxy,
    :event_broker,
    :webhook,
    :oban_queues
  ]

  @doc """
  Converts parsed raw metrics map to structured AdminMetrics.
  """
  def from_raw_metrics(raw_metrics) do
    %__MODULE__{
      timestamp: DateTime.utc_now(),
      application: Application.from_raw(raw_metrics),
      metadata: Metadata.from_raw(raw_metrics),
      membership: Membership.from_raw(raw_metrics),
      discovery: Discovery.from_raw(raw_metrics),
      nodes: Nodes.from_raw(raw_metrics),
      quantum: Quantum.from_raw(raw_metrics),
      vpn: Vpn.from_raw(raw_metrics),
      commands: Commands.from_raw(raw_metrics),
      ssh: Ssh.from_raw(raw_metrics),
      reconciliation: Reconciliation.from_raw(raw_metrics),
      self_updates: SelfUpdates.from_raw(raw_metrics),
      gateways: Gateways.from_raw(raw_metrics),
      proxy: Proxy.from_raw(raw_metrics),
      event_broker: EventBroker.from_raw(raw_metrics),
      webhook: Webhook.from_raw(raw_metrics),
      oban_queues: ObanQueue.from_raw(raw_metrics)
    }
  end

  defmodule Application do
    @moduledoc "Application health and BEAM stats"

    @derive JSON.Encoder
    defstruct [
      :uptime_seconds,
      :uptime_human,
      :process_count,
      :port_count,
      :atom_count,
      :ets_count,
      :memory_total_bytes,
      :memory_total_mb,
      :memory_processes_bytes,
      :memory_processes_mb,
      :memory_ets_bytes,
      :memory_ets_mb,
      :memory_binary_bytes,
      :memory_binary_mb,
      :memory_code_bytes,
      :memory_code_mb,
      :memory_atom_bytes,
      :memory_atom_mb
    ]

    def from_raw(raw) do
      uptime_seconds = div(raw["uptime_ms"] || 0, 1000)

      %__MODULE__{
        uptime_seconds: uptime_seconds,
        uptime_human: format_uptime(uptime_seconds),
        process_count: raw["process_count"],
        port_count: raw["port_count"],
        atom_count: raw["atom_count"],
        ets_count: raw["ets_count"],
        memory_total_bytes: raw["memory_total"],
        memory_total_mb: bytes_to_mb(raw["memory_total"]),
        memory_processes_bytes: raw["memory_processes"],
        memory_processes_mb: bytes_to_mb(raw["memory_processes"]),
        memory_ets_bytes: raw["memory_ets"],
        memory_ets_mb: bytes_to_mb(raw["memory_ets"]),
        memory_binary_bytes: raw["memory_binary"],
        memory_binary_mb: bytes_to_mb(raw["memory_binary"]),
        memory_code_bytes: raw["memory_code"],
        memory_code_mb: bytes_to_mb(raw["memory_code"]),
        memory_atom_bytes: raw["memory_atom"],
        memory_atom_mb: bytes_to_mb(raw["memory_atom"])
      }
    end

    defp bytes_to_mb(nil), do: nil
    defp bytes_to_mb(bytes), do: Float.round(bytes / 1_048_576, 2)

    defp format_uptime(seconds) when seconds < 60, do: "#{seconds}s"

    defp format_uptime(seconds) when seconds < 3600 do
      minutes = div(seconds, 60)
      "#{minutes}m"
    end

    defp format_uptime(seconds) when seconds < 86_400 do
      hours = div(seconds, 3600)
      minutes = div(rem(seconds, 3600), 60)
      "#{hours}h #{minutes}m"
    end

    defp format_uptime(seconds) do
      days = div(seconds, 86_400)
      hours = div(rem(seconds, 86_400), 3600)
      minutes = div(rem(seconds, 3600), 60)
      "#{days}d #{hours}h #{minutes}m"
    end
  end

  defmodule Metadata do
    @moduledoc "Admin metadata and cluster assignment metrics"

    @derive JSON.Encoder
    defstruct [
      :degraded,
      :orphaned_clusters,
      :assigned_clusters,
      :recomputations_total
    ]

    def from_raw(raw) do
      %__MODULE__{
        degraded: raw["metadata_degraded"] == 1,
        orphaned_clusters: raw["metadata_orphaned_clusters"],
        assigned_clusters: raw["metadata_assigned_clusters"],
        recomputations_total: raw["metadata_recomputations"]
      }
    end
  end

  defmodule Membership do
    @moduledoc "Admin-cluster membership initialization metrics"

    @derive JSON.Encoder
    defstruct [
      :steps_completed_total,
      :complete_total
    ]

    def from_raw(raw) do
      %__MODULE__{
        steps_completed_total: raw["membership_steps"],
        complete_total: raw["membership_complete_total"]
      }
    end
  end

  defmodule Discovery do
    @moduledoc "Peer admin discovery metrics"

    @derive JSON.Encoder
    defstruct [
      :scans_total,
      :dns_resolutions_total,
      :peer_connections_total
    ]

    def from_raw(raw) do
      %__MODULE__{
        scans_total: raw["discovery_scans_total"],
        dns_resolutions_total: raw["discovery_dns_resolutions_total"],
        peer_connections_total: raw["discovery_peer_connections_total"]
      }
    end
  end

  defmodule Nodes do
    @moduledoc "Node health check metrics"

    @derive JSON.Encoder
    defstruct [
      :health_checks_total
    ]

    def from_raw(raw) do
      %__MODULE__{
        health_checks_total: raw["nodes_health_checks"]
      }
    end
  end

  defmodule Quantum do
    @moduledoc "Quantum scheduler job execution metrics"

    @derive JSON.Encoder
    defstruct [
      :jobs_executed_total,
      :jobs_exceptions_total
    ]

    def from_raw(raw) do
      %__MODULE__{
        jobs_executed_total: raw["quantum_jobs_executed"],
        jobs_exceptions_total: raw["quantum_jobs_exceptions"]
      }
    end
  end

  defmodule Vpn do
    @moduledoc "VPN management metrics"

    @derive JSON.Encoder
    defstruct [
      :zombie_cleanup_total,
      :zombie_cleanup_deleted_count
    ]

    def from_raw(raw) do
      %__MODULE__{
        zombie_cleanup_total: raw["vpn_zombie_cleanup_total"],
        zombie_cleanup_deleted_count: raw["vpn_zombie_cleanup_deleted_count"]
      }
    end
  end

  defmodule Commands do
    @moduledoc "Command execution and delivery metrics"

    @derive JSON.Encoder
    defstruct [
      :delivery_total,
      :delivery_delivered_count,
      :execution_delivered_total,
      :execution_completed_total,
      :expiration_total,
      :pruning_total,
      :pruning_deleted_count
    ]

    def from_raw(raw) do
      %__MODULE__{
        delivery_total: raw["commands_delivery_total"],
        delivery_delivered_count: raw["commands_delivery_delivered_count"],
        execution_delivered_total: raw["commands_execution_delivered_total"],
        execution_completed_total: raw["commands_execution_completed_total"],
        expiration_total: raw["commands_expiration_total"],
        pruning_total: raw["commands_pruning_total"],
        pruning_deleted_count: raw["commands_pruning_deleted_count"]
      }
    end
  end

  defmodule Ssh do
    @moduledoc "SSH credential verification metrics"

    @derive JSON.Encoder
    defstruct [
      :verifications_total,
      :verifications_failed
    ]

    def from_raw(raw) do
      %__MODULE__{
        verifications_total: raw["ssh_verifications_total"],
        verifications_failed: raw["ssh_verifications_failed"]
      }
    end
  end

  defmodule Reconciliation do
    @moduledoc "Cluster reconciliation metrics"

    @derive JSON.Encoder
    defstruct [
      :total,
      :errors
    ]

    def from_raw(raw) do
      %__MODULE__{
        total: raw["nodes_cluster_reconciliations_total"],
        errors: raw["nodes_cluster_reconciliation_errors"]
      }
    end
  end

  defmodule SelfUpdates do
    @moduledoc "Self-update request processing metrics"

    @derive JSON.Encoder
    defstruct [
      :completed_total
    ]

    def from_raw(raw) do
      %__MODULE__{
        completed_total: raw["self_updates_completed_total"]
      }
    end
  end

  defmodule Gateways do
    @moduledoc "Gateway connection and scrape metrics"

    @derive JSON.Encoder
    defstruct [
      :connections_total,
      :active_count,
      :scrapes_total
    ]

    def from_raw(raw) do
      %__MODULE__{
        connections_total: raw["gateway_connections_total"],
        active_count: raw["gateway_active_count"],
        scrapes_total: raw["gateway_scrapes_total"]
      }
    end
  end

  defmodule Proxy do
    @moduledoc "HTTP and SOCKS5 forward proxy metrics"

    @derive JSON.Encoder
    defstruct [
      :connections_total,
      :connections_success_total,
      :connections_auth_failed_total,
      :connections_failure_total,
      :auth_failures_total,
      :tunnels_closed_total,
      :tunnels_closed_normal_total,
      :tunnels_closed_deadline_total,
      :tunnels_closed_drain_timeout_total,
      :bytes_up_total,
      :bytes_up_mb,
      :bytes_down_total,
      :bytes_down_mb
    ]

    def from_raw(raw) do
      bytes_up = raw["proxy_tunnel_bytes_up_total"]
      bytes_down = raw["proxy_tunnel_bytes_down_total"]

      %__MODULE__{
        connections_total: raw["proxy_connections_total"],
        connections_success_total: raw["proxy_connections_success_total"],
        connections_auth_failed_total: raw["proxy_connections_auth_failed_total"],
        connections_failure_total: raw["proxy_connections_failure_total"],
        auth_failures_total: raw["proxy_auth_failures_total"],
        tunnels_closed_total: raw["proxy_tunnels_closed_total"],
        tunnels_closed_normal_total: raw["proxy_tunnels_closed_normal_total"],
        tunnels_closed_deadline_total: raw["proxy_tunnels_closed_deadline_total"],
        tunnels_closed_drain_timeout_total: raw["proxy_tunnels_closed_drain_timeout_total"],
        bytes_up_total: bytes_up,
        bytes_up_mb: bytes_to_mb(bytes_up),
        bytes_down_total: bytes_down,
        bytes_down_mb: bytes_to_mb(bytes_down)
      }
    end

    defp bytes_to_mb(nil), do: nil
    defp bytes_to_mb(bytes), do: Float.round(bytes / 1_048_576, 2)
  end

  defmodule EventBroker do
    @moduledoc """
    Event broker publish metrics.

    `enabled` reflects the `:event_broker_enabled` application config — when
    `false`, all counters will be 0 because no telemetry events are emitted
    (the broker short-circuits at the call site).

    `enqueues_total` minus `publishes_ok_total` is the backlog signal: a
    sustained gap means events are piling up in Oban because the broker is
    failing to accept them.
    """

    @derive JSON.Encoder
    defstruct [
      :enabled,
      :enqueues_total,
      :publishes_total,
      :publishes_ok_total,
      :publishes_error_total
    ]

    def from_raw(raw) do
      %__MODULE__{
        enabled: Elixir.Application.get_env(:edge_admin, :event_broker_enabled, false),
        enqueues_total: raw["event_broker_enqueues_total"],
        publishes_total: raw["event_broker_publishes_total"],
        publishes_ok_total: raw["event_broker_publishes_ok_total"],
        publishes_error_total: raw["event_broker_publishes_error_total"]
      }
    end
  end

  defmodule Webhook do
    @moduledoc """
    Webhook delivery metrics.

    `fan_outs_total` is one increment per `Events.publish/1` invocation that
    saw at least one matching webhook (the underlying counter records the
    matched count as the measurement).

    `deliveries_*` count individual HTTP attempts and split by outcome:
      - `ok`           — 2xx response
      - `recoverable`  — 408/429/503/network; will be retried by Oban
      - `terminal`     — other 4xx/5xx; cancelled, contributes to auto-disable
    """

    @derive JSON.Encoder
    defstruct [
      :fan_outs_total,
      :deliveries_total,
      :deliveries_ok_total,
      :deliveries_recoverable_total,
      :deliveries_terminal_total
    ]

    def from_raw(raw) do
      %__MODULE__{
        fan_outs_total: raw["webhook_fan_outs_total"],
        deliveries_total: raw["webhook_deliveries_total"],
        deliveries_ok_total: raw["webhook_deliveries_ok_total"],
        deliveries_recoverable_total: raw["webhook_deliveries_recoverable_total"],
        deliveries_terminal_total: raw["webhook_deliveries_terminal_total"]
      }
    end
  end

  defmodule ObanQueue do
    @moduledoc "Oban job queue state"

    @derive JSON.Encoder
    defstruct [
      :queue,
      :available,
      :scheduled,
      :executing,
      :retryable,
      :completed,
      :discarded,
      :cancelled
    ]

    def from_raw(raw) do
      Enum.map(raw["oban_queues"] || [], fn queue ->
        %__MODULE__{
          queue: queue["queue"],
          available: queue["available"],
          scheduled: queue["scheduled"],
          executing: queue["executing"],
          retryable: queue["retryable"],
          completed: queue["completed"],
          discarded: queue["discarded"],
          cancelled: queue["cancelled"]
        }
      end)
    end
  end
end
