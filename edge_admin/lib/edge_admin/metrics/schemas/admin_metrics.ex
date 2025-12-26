# edge_admin/lib/edge_admin/metrics/schemas/admin_metrics.ex
defmodule EdgeAdmin.Metrics.Schemas.AdminMetrics do
  @moduledoc """
  Schema for human-friendly admin application metrics.
  """

  alias EdgeAdmin.Metrics.Schemas.AdminMetrics.{Application, Metadata, Bootstrap, Nodes, Quantum, Vpn, Commands, Gateways, ObanQueue}

  @derive Jason.Encoder
  defstruct [
    :timestamp,
    :application,
    :metadata,
    :bootstrap,
    :nodes,
    :quantum,
    :vpn,
    :commands,
    :gateways,
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
      bootstrap: Bootstrap.from_raw(raw_metrics),
      nodes: Nodes.from_raw(raw_metrics),
      quantum: Quantum.from_raw(raw_metrics),
      vpn: Vpn.from_raw(raw_metrics),
      commands: Commands.from_raw(raw_metrics),
      gateways: Gateways.from_raw(raw_metrics),
      oban_queues: ObanQueue.from_raw(raw_metrics)
    }
  end

  defmodule Application do
    @moduledoc "Application health and BEAM stats"

    @derive Jason.Encoder
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
    defp format_uptime(seconds) when seconds < 86400 do
      hours = div(seconds, 3600)
      minutes = div(rem(seconds, 3600), 60)
      "#{hours}h #{minutes}m"
    end
    defp format_uptime(seconds) do
      days = div(seconds, 86400)
      hours = div(rem(seconds, 86400), 3600)
      minutes = div(rem(seconds, 3600), 60)
      "#{days}d #{hours}h #{minutes}m"
    end
  end

  defmodule Metadata do
    @moduledoc "Admin metadata and cluster assignment metrics"

    @derive Jason.Encoder
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

  defmodule Bootstrap do
    @moduledoc "Bootstrap initialization metrics"

    @derive Jason.Encoder
    defstruct [
      :steps_completed_total
    ]

    def from_raw(raw) do
      %__MODULE__{
        steps_completed_total: raw["bootstrap_steps"]
      }
    end
  end

  defmodule Nodes do
    @moduledoc "Node health check metrics"

    @derive Jason.Encoder
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

    @derive Jason.Encoder
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

    @derive Jason.Encoder
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

    @derive Jason.Encoder
    defstruct [
      :delivery_total,
      :delivery_delivered_count
    ]

    def from_raw(raw) do
      %__MODULE__{
        delivery_total: raw["commands_delivery_total"],
        delivery_delivered_count: raw["commands_delivery_delivered_count"]
      }
    end
  end

  defmodule Gateways do
    @moduledoc "Gateway connection and scrape metrics"

    @derive Jason.Encoder
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

  defmodule ObanQueue do
    @moduledoc "Oban job queue state"

    @derive Jason.Encoder
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
