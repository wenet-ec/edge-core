# edge_admin/lib/edge_admin/metrics/schemas/host_metrics.ex
defmodule EdgeAdmin.Metrics.Schemas.HostMetrics do
  @moduledoc """
  Schema for human-friendly host-level metrics.

  Represents system metrics from Node Exporter including CPU, memory, disk, and uptime.
  """

  alias EdgeAdmin.Metrics.Schemas.HostMetrics.CPU
  alias EdgeAdmin.Metrics.Schemas.HostMetrics.Disk
  alias EdgeAdmin.Metrics.Schemas.HostMetrics.Memory
  alias EdgeAdmin.Metrics.Schemas.HostMetrics.Uptime

  @type t :: %__MODULE__{}

  @derive Jason.Encoder
  defstruct [
    :node_id,
    :cluster_name,
    :timestamp,
    :cpu,
    :memory,
    :disk,
    :uptime
  ]

  @doc """
  Converts parsed raw metrics map to structured HostMetrics.
  """
  def from_raw_metrics(raw_metrics, node_id) do
    %__MODULE__{
      node_id: node_id,
      cluster_name: raw_metrics["cluster_name"],
      timestamp: DateTime.utc_now(),
      cpu: CPU.from_raw(raw_metrics),
      memory: Memory.from_raw(raw_metrics),
      disk: Disk.from_raw(raw_metrics),
      uptime: Uptime.from_raw(raw_metrics)
    }
  end

  defmodule CPU do
    @moduledoc "CPU metrics"

    @derive Jason.Encoder
    defstruct [
      :cores,
      :load_1m,
      :load_5m,
      :load_15m
    ]

    def from_raw(raw) do
      %__MODULE__{
        cores: trunc_or_nil(raw["cpu_cores"]),
        load_1m: round_to_2dp(raw["load_1m"]),
        load_5m: round_to_2dp(raw["load_5m"]),
        load_15m: round_to_2dp(raw["load_15m"])
      }
    end

    defp round_to_2dp(nil), do: nil
    defp round_to_2dp(value), do: Float.round(value, 2)

    defp trunc_or_nil(nil), do: nil
    defp trunc_or_nil(value), do: trunc(value)
  end

  defmodule Memory do
    @moduledoc "Memory metrics"

    @derive Jason.Encoder
    defstruct [
      :usage_percent,
      :total_bytes,
      :available_bytes,
      :used_bytes,
      :total_gb,
      :available_gb,
      :used_gb
    ]

    def from_raw(raw) do
      total_bytes = raw["memory_total_bytes"]
      available_bytes = raw["memory_available_bytes"]
      used_bytes = if total_bytes && available_bytes, do: total_bytes - available_bytes

      %__MODULE__{
        usage_percent: round_to_2dp(raw["memory_usage_percent"]),
        total_bytes: trunc_or_nil(total_bytes),
        available_bytes: trunc_or_nil(available_bytes),
        used_bytes: trunc_or_nil(used_bytes),
        total_gb: bytes_to_gb(total_bytes),
        available_gb: bytes_to_gb(available_bytes),
        used_gb: bytes_to_gb(used_bytes)
      }
    end

    defp round_to_2dp(nil), do: nil
    defp round_to_2dp(value), do: Float.round(value, 2)

    defp trunc_or_nil(nil), do: nil
    defp trunc_or_nil(value), do: trunc(value)

    defp bytes_to_gb(nil), do: nil
    defp bytes_to_gb(bytes), do: Float.round(bytes / 1_073_741_824, 1)
  end

  defmodule Disk do
    @moduledoc "Disk metrics for root filesystem"

    @derive Jason.Encoder
    defstruct [
      :usage_percent,
      :total_bytes,
      :available_bytes,
      :used_bytes,
      :total_gb,
      :available_gb,
      :used_gb
    ]

    def from_raw(raw) do
      total_bytes = raw["disk_total_bytes"]
      available_bytes = raw["disk_available_bytes"]
      used_bytes = if total_bytes && available_bytes, do: total_bytes - available_bytes

      %__MODULE__{
        usage_percent: round_to_2dp(raw["disk_usage_percent"]),
        total_bytes: trunc_or_nil(total_bytes),
        available_bytes: trunc_or_nil(available_bytes),
        used_bytes: trunc_or_nil(used_bytes),
        total_gb: bytes_to_gb(total_bytes),
        available_gb: bytes_to_gb(available_bytes),
        used_gb: bytes_to_gb(used_bytes)
      }
    end

    defp round_to_2dp(nil), do: nil
    defp round_to_2dp(value), do: Float.round(value, 2)

    defp trunc_or_nil(nil), do: nil
    defp trunc_or_nil(value), do: trunc(value)

    defp bytes_to_gb(nil), do: nil
    defp bytes_to_gb(bytes), do: Float.round(bytes / 1_073_741_824, 1)
  end

  defmodule Uptime do
    @moduledoc "System uptime"

    @derive Jason.Encoder
    defstruct [
      :seconds,
      :human
    ]

    def from_raw(raw) do
      uptime_seconds = raw["uptime_seconds"]

      %__MODULE__{
        seconds: trunc_or_nil(uptime_seconds),
        human: if(uptime_seconds, do: format_uptime(trunc(uptime_seconds)))
      }
    end

    defp trunc_or_nil(nil), do: nil
    defp trunc_or_nil(value), do: trunc(value)

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
end
