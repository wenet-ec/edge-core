# edge_admin_web/live/netmaker_dashboard/collector.ex
defmodule EdgeAdminWeb.Live.NetmakerDashboard.Collector do
  @moduledoc """
  Telemetry event collector for Netmaker API metrics.

  Attaches to Finch telemetry events and aggregates statistics in ETS.
  Stats are retained for 1 hour and automatically pruned.
  """

  use GenServer

  require Logger

  @table_name :netmaker_dashboard_stats
  @cleanup_interval to_timeout(minute: 5)
  @retention_period to_timeout(hour: 1)

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current Netmaker API statistics.
  """
  def get_stats do
    case :ets.lookup(@table_name, :stats) do
      [{:stats, stats}] -> stats
      [] -> default_stats()
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
    :ets.insert(@table_name, {:stats, default_stats()})

    :ets.new(:netmaker_request_history, [
      :named_table,
      :ordered_set,
      :public,
      read_concurrency: true
    ])

    :ets.new(:netmaker_error_history, [
      :named_table,
      :ordered_set,
      :public,
      read_concurrency: true
    ])

    # Attach telemetry handlers
    events = [
      [:finch, :request, :start],
      [:finch, :request, :stop],
      [:finch, :request, :exception],
      [:finch, :connect, :stop],
      [:finch, :reused_connection]
    ]

    :telemetry.attach_many(
      "netmaker-dashboard-collector",
      events,
      &__MODULE__.handle_event/4,
      nil
    )

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval)

    Logger.info("NetmakerDashboard.Collector started and attached to Finch telemetry")

    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_events()
    Process.send_after(self(), :cleanup, @cleanup_interval)
    {:noreply, state}
  end

  # Telemetry Event Handlers

  def handle_event([:finch, :request, :start], measurements, _metadata, _config) do
    timestamp = System.system_time(:millisecond)
    :ets.insert(:netmaker_request_history, {timestamp, :start, measurements})
    :ok
  end

  def handle_event([:finch, :request, :stop], measurements, metadata, _config) do
    timestamp = System.system_time(:millisecond)
    duration = Map.get(measurements, :duration, 0)

    :ets.insert(:netmaker_request_history, {timestamp, :stop, %{duration: duration}})
    update_stats(:request_success, duration)

    Logger.debug("Netmaker API request completed",
      duration_ms: System.convert_time_unit(duration, :native, :millisecond),
      name: Map.get(metadata, :name)
    )

    :ok
  end

  def handle_event([:finch, :request, :exception], measurements, metadata, _config) do
    timestamp = DateTime.utc_now()
    duration = Map.get(measurements, :duration, 0)
    kind = Map.get(metadata, :kind, :unknown)
    reason = Map.get(metadata, :reason, :unknown)

    error = %{
      timestamp: timestamp,
      kind: kind,
      reason: reason,
      duration: duration
    }

    # Store error (keep last 20)
    :ets.insert(:netmaker_error_history, {System.system_time(:millisecond), error})
    update_stats(:request_failure, duration)

    Logger.warning("Netmaker API request failed",
      kind: kind,
      reason: inspect(reason),
      duration_ms: System.convert_time_unit(duration, :native, :millisecond)
    )

    :ok
  end

  def handle_event([:finch, :connect, :stop], measurements, metadata, _config) do
    duration = Map.get(measurements, :duration, 0)
    update_stats(:new_connection, duration)

    Logger.debug("New Netmaker API connection established",
      host: Map.get(metadata, :host),
      duration_ms: System.convert_time_unit(duration, :native, :millisecond)
    )

    :ok
  end

  def handle_event([:finch, :reused_connection], _measurements, metadata, _config) do
    update_stats(:reused_connection, 0)

    Logger.debug("Netmaker API connection reused", host: Map.get(metadata, :host))

    :ok
  end

  # Private Helpers

  defp default_stats do
    %{
      total_requests: 0,
      successful_requests: 0,
      failed_requests: 0,
      connections_reused: 0,
      new_connections: 0,
      avg_duration: 0,
      min_duration: nil,
      max_duration: nil,
      p95_duration: nil,
      recent_errors: []
    }
  end

  defp update_stats(event_type, duration) do
    [{:stats, stats}] = :ets.lookup(@table_name, :stats)

    updated_stats =
      case event_type do
        :request_success ->
          stats
          |> Map.update!(:total_requests, &(&1 + 1))
          |> Map.update!(:successful_requests, &(&1 + 1))
          |> update_duration_stats(duration)

        :request_failure ->
          stats
          |> Map.update!(:total_requests, &(&1 + 1))
          |> Map.update!(:failed_requests, &(&1 + 1))
          |> update_error_list()

        :new_connection ->
          Map.update!(stats, :new_connections, &(&1 + 1))

        :reused_connection ->
          Map.update!(stats, :connections_reused, &(&1 + 1))
      end

    :ets.insert(@table_name, {:stats, updated_stats})
  end

  defp update_duration_stats(stats, duration) do
    stats
    |> Map.update!(:avg_duration, fn avg ->
      total = stats.total_requests
      (avg * total + duration) / (total + 1)
    end)
    |> Map.update!(:min_duration, fn
      nil -> duration
      min -> min(min, duration)
    end)
    |> Map.update!(:max_duration, fn
      nil -> duration
      max -> max(max, duration)
    end)
    |> update_p95_duration()
  end

  defp update_p95_duration(stats) do
    # Get recent durations from history and calculate P95
    recent_durations =
      :netmaker_request_history
      |> :ets.tab2list()
      |> Enum.filter(fn {_ts, type, _data} -> type == :stop end)
      |> Enum.map(fn {_ts, _type, data} -> data.duration end)
      |> Enum.sort()

    p95 = calculate_percentile(recent_durations, 95)
    Map.put(stats, :p95_duration, p95)
  end

  defp update_error_list(stats) do
    recent_errors =
      :netmaker_error_history
      |> :ets.tab2list()
      |> Enum.sort_by(fn {ts, _error} -> ts end, :desc)
      |> Enum.take(20)
      |> Enum.map(fn {_ts, error} -> error end)

    Map.put(stats, :recent_errors, recent_errors)
  end

  defp calculate_percentile([], _percentile), do: nil
  defp calculate_percentile([single], _percentile), do: single

  defp calculate_percentile(sorted_list, percentile) do
    k = (length(sorted_list) - 1) * percentile / 100
    f = floor(k)
    c = ceil(k)

    if f == c do
      Enum.at(sorted_list, round(k))
    else
      d0 = Enum.at(sorted_list, f) * (c - k)
      d1 = Enum.at(sorted_list, c) * (k - f)
      round(d0 + d1)
    end
  end

  defp cleanup_old_events do
    cutoff = System.system_time(:millisecond) - @retention_period

    # Clean up request history
    :ets.select_delete(:netmaker_request_history, [
      {{:"$1", :_, :_}, [{:<, :"$1", cutoff}], [true]}
    ])

    # Clean up error history
    :ets.select_delete(:netmaker_error_history, [
      {{:"$1", :_}, [{:<, :"$1", cutoff}], [true]}
    ])

    Logger.debug("Cleaned up Netmaker dashboard events older than 1 hour")
  end
end
