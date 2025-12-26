# edge_admin/lib/edge_admin/metrics/schemas/host_metrics.ex
defmodule EdgeAdmin.Metrics.Schemas.HostMetrics do
  @moduledoc """
  Embedded schema for host-level metrics with validation and formatting.

  Represents system metrics from Node Exporter including CPU, memory, disk, and uptime.
  This schema provides structured data handling with validation, type conversion, and
  consistent formatting.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias EdgeAdmin.Metrics.Schemas.HostMetrics.CPU
  alias EdgeAdmin.Metrics.Schemas.HostMetrics.Disk
  alias EdgeAdmin.Metrics.Schemas.HostMetrics.Memory
  alias EdgeAdmin.Metrics.Schemas.HostMetrics.Uptime

  @derive Jason.Encoder
  @primary_key false
  embedded_schema do
    field(:node_id, :binary_id)
    field(:cluster_name, :string)
    field(:timestamp, :utc_datetime)

    embeds_one(:cpu, CPU)
    embeds_one(:memory, Memory)
    embeds_one(:disk, Disk)
    embeds_one(:uptime, Uptime)
  end

  def from_raw_metrics(raw_metrics, node_id) do
    attrs = %{
      node_id: node_id,
      cluster_name: raw_metrics["cluster_name"],
      timestamp: DateTime.utc_now(),
      cpu: build_cpu_attrs(raw_metrics),
      memory: build_memory_attrs(raw_metrics),
      disk: build_disk_attrs(raw_metrics),
      uptime: build_uptime_attrs(raw_metrics)
    }

    %__MODULE__{}
    |> changeset(attrs)
    |> apply_action!(:validate)
  end

  @doc false
  def changeset(metrics, attrs) do
    metrics
    |> cast(attrs, [:node_id, :cluster_name, :timestamp])
    |> cast_embed(:cpu, with: &cpu_changeset/2)
    |> cast_embed(:memory, with: &memory_changeset/2)
    |> cast_embed(:disk, with: &disk_changeset/2)
    |> cast_embed(:uptime, with: &uptime_changeset/2)
    |> validate_required([:node_id, :cluster_name, :timestamp])
  end

  # CPU changeset with validation
  defp cpu_changeset(cpu, attrs) do
    cpu
    |> cast(attrs, [:cores, :load_1m, :load_5m, :load_15m])
    |> validate_number(:cores, greater_than: 0)
    |> validate_number(:load_1m, greater_than_or_equal_to: 0)
    |> validate_number(:load_5m, greater_than_or_equal_to: 0)
    |> validate_number(:load_15m, greater_than_or_equal_to: 0)
  end

  # Memory changeset with validation and calculated fields
  defp memory_changeset(memory, attrs) do
    memory
    |> cast(attrs, [
      :usage_percent,
      :total_bytes,
      :available_bytes,
      :used_bytes,
      :total_gb,
      :available_gb,
      :used_gb
    ])
    |> validate_number(:usage_percent, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:total_bytes, greater_than: 0)
    |> validate_number(:available_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:used_bytes, greater_than_or_equal_to: 0)
    |> validate_memory_consistency()
  end

  # Disk changeset with validation and calculated fields
  defp disk_changeset(disk, attrs) do
    disk
    |> cast(attrs, [
      :usage_percent,
      :total_bytes,
      :available_bytes,
      :used_bytes,
      :total_gb,
      :available_gb,
      :used_gb
    ])
    |> validate_number(:usage_percent, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:total_bytes, greater_than: 0)
    |> validate_number(:available_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:used_bytes, greater_than_or_equal_to: 0)
    |> validate_disk_consistency()
  end

  # Uptime changeset with validation
  defp uptime_changeset(uptime, attrs) do
    uptime
    |> cast(attrs, [:seconds, :human])
    |> validate_number(:seconds, greater_than_or_equal_to: 0)
    |> validate_length(:human, max: 50)
  end

  # Validation helpers
  defp validate_memory_consistency(changeset) do
    total = get_field(changeset, :total_bytes)
    available = get_field(changeset, :available_bytes)
    used = get_field(changeset, :used_bytes)

    if total && available && used && available + used > total * 1.1 do
      add_error(changeset, :used_bytes, "memory calculations are inconsistent")
    else
      changeset
    end
  end

  defp validate_disk_consistency(changeset) do
    total = get_field(changeset, :total_bytes)
    available = get_field(changeset, :available_bytes)
    used = get_field(changeset, :used_bytes)

    if total && available && used && available + used > total * 1.1 do
      add_error(changeset, :used_bytes, "disk calculations are inconsistent")
    else
      changeset
    end
  end

  # Attribute builders for each metric type
  defp build_cpu_attrs(raw_metrics) do
    %{
      cores: trunc_or_nil(raw_metrics["cpu_cores"]),
      load_1m: round_to_2dp(raw_metrics["load_1m"]),
      load_5m: round_to_2dp(raw_metrics["load_5m"]),
      load_15m: round_to_2dp(raw_metrics["load_15m"])
    }
  end

  defp build_memory_attrs(raw_metrics) do
    total_bytes = raw_metrics["memory_total_bytes"]
    available_bytes = raw_metrics["memory_available_bytes"]
    used_bytes = if total_bytes && available_bytes, do: total_bytes - available_bytes

    %{
      usage_percent: round_to_2dp(raw_metrics["memory_usage_percent"]),
      total_bytes: trunc_or_nil(total_bytes),
      available_bytes: trunc_or_nil(available_bytes),
      used_bytes: trunc_or_nil(used_bytes),
      total_gb: bytes_to_gb(total_bytes),
      available_gb: bytes_to_gb(available_bytes),
      used_gb: bytes_to_gb(used_bytes)
    }
  end

  defp build_disk_attrs(raw_metrics) do
    total_bytes = raw_metrics["disk_total_bytes"]
    available_bytes = raw_metrics["disk_available_bytes"]
    used_bytes = if total_bytes && available_bytes, do: total_bytes - available_bytes

    %{
      usage_percent: round_to_2dp(raw_metrics["disk_usage_percent"]),
      total_bytes: trunc_or_nil(total_bytes),
      available_bytes: trunc_or_nil(available_bytes),
      used_bytes: trunc_or_nil(used_bytes),
      total_gb: bytes_to_gb(total_bytes),
      available_gb: bytes_to_gb(available_bytes),
      used_gb: bytes_to_gb(used_bytes)
    }
  end

  defp build_uptime_attrs(raw_metrics) do
    uptime_seconds = raw_metrics["uptime_seconds"]

    %{
      seconds: trunc_or_nil(uptime_seconds),
      human: if(uptime_seconds, do: format_uptime_human(trunc(uptime_seconds)))
    }
  end

  # Helper functions
  defp round_to_2dp(nil), do: nil
  defp round_to_2dp(value), do: Float.round(value, 2)

  defp trunc_or_nil(nil), do: nil
  defp trunc_or_nil(value), do: trunc(value)

  defp bytes_to_gb(nil), do: nil
  defp bytes_to_gb(bytes), do: Float.round(bytes / 1_073_741_824, 1)

  defp format_uptime_human(seconds) do
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3600)
    minutes = div(rem(seconds, 3600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{minutes}m"
      hours > 0 -> "#{hours}h #{minutes}m"
      true -> "#{minutes}m"
    end
  end
end
