# edge_admin/lib/edge_admin/metrics/schemas/agent_metrics.ex
defmodule EdgeAdmin.Metrics.Schemas.AgentMetrics do
  @moduledoc """
  Schema for human-friendly agent application metrics.
  """

  alias EdgeAdmin.Metrics.Schemas.AgentMetrics.{Application, Commands, Discovery, ObanQueue, Proxy, Ssh}

  @derive Jason.Encoder
  defstruct [
    :node_id,
    :cluster_name,
    :timestamp,
    :application,
    :commands,
    :discovery,
    :proxy,
    :ssh,
    :oban_queues
  ]

  @doc """
  Converts parsed raw metrics map to structured AgentMetrics.
  """
  def from_raw_metrics(raw_metrics, node_id) do
    %__MODULE__{
      node_id: node_id,
      cluster_name: raw_metrics["cluster_name"],
      timestamp: DateTime.utc_now(),
      application: Application.from_raw(raw_metrics),
      commands: Commands.from_raw(raw_metrics),
      discovery: Discovery.from_raw(raw_metrics),
      proxy: Proxy.from_raw(raw_metrics),
      ssh: Ssh.from_raw(raw_metrics),
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
      :memory_total_bytes,
      :memory_total_mb,
      :memory_processes_bytes,
      :memory_processes_mb,
      :memory_ets_bytes,
      :memory_ets_mb,
      :memory_binary_bytes,
      :memory_binary_mb
    ]

    def from_raw(raw) do
      uptime_seconds = div(raw["uptime_ms"] || 0, 1000)

      %__MODULE__{
        uptime_seconds: uptime_seconds,
        uptime_human: format_uptime(uptime_seconds),
        process_count: raw["process_count"],
        memory_total_bytes: raw["memory_total"],
        memory_total_mb: bytes_to_mb(raw["memory_total"]),
        memory_processes_bytes: raw["memory_processes"],
        memory_processes_mb: bytes_to_mb(raw["memory_processes"]),
        memory_ets_bytes: raw["memory_ets"],
        memory_ets_mb: bytes_to_mb(raw["memory_ets"]),
        memory_binary_bytes: raw["memory_binary"],
        memory_binary_mb: bytes_to_mb(raw["memory_binary"])
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

  defmodule Commands do
    @moduledoc "Command execution metrics"

    @derive Jason.Encoder
    defstruct [
      :synced_total,
      :enqueued_total,
      :completed_total,
      :reported_total
    ]

    def from_raw(raw) do
      %__MODULE__{
        synced_total: raw["commands_synced"] || 0,
        enqueued_total: raw["commands_enqueued"] || 0,
        completed_total: raw["commands_completed"] || 0,
        reported_total: raw["commands_reported"] || 0
      }
    end
  end

  defmodule Discovery do
    @moduledoc "Admin discovery metrics"

    @derive Jason.Encoder
    defstruct [
      :scans_total,
      :admins_found_last
    ]

    def from_raw(raw) do
      %__MODULE__{
        scans_total: raw["discovery_scans"] || 0,
        admins_found_last: raw["admins_found"] || 0
      }
    end
  end

  defmodule Proxy do
    @moduledoc "Proxy server metrics"

    @derive Jason.Encoder
    defstruct [
      :http_connections_total,
      :socks5_connections_total
    ]

    def from_raw(raw) do
      %__MODULE__{
        http_connections_total: raw["proxy_http_connections"] || 0,
        socks5_connections_total: raw["proxy_socks5_connections"] || 0
      }
    end
  end

  defmodule Ssh do
    @moduledoc "SSH server metrics"

    @derive Jason.Encoder
    defstruct [
      :authentications_total,
      :connections_total
    ]

    def from_raw(raw) do
      %__MODULE__{
        authentications_total: raw["ssh_authentications"] || 0,
        connections_total: raw["ssh_connections"] || 0
      }
    end
  end

  defmodule ObanQueue do
    @moduledoc "Oban queue metrics"

    @derive Jason.Encoder
    defstruct [:queue, :available, :executing, :completed, :discarded, :retryable]

    def from_raw(raw) do
      (raw["oban_queues"] || [])
      |> Enum.map(fn queue_data ->
        states = queue_data["states"]

        %__MODULE__{
          queue: queue_data["queue"],
          available: states["available"],
          executing: states["executing"],
          completed: states["completed"],
          discarded: states["discarded"],
          retryable: states["retryable"]
        }
      end)
    end
  end
end
