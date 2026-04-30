# edge_admin/lib/edge_admin/local_scheduler/history.ex
defmodule EdgeAdmin.LocalScheduler.History do
  @moduledoc """
  Per-job last-run history for `EdgeAdmin.LocalScheduler`.

  Attaches to Quantum's `[:quantum, :job, :stop | :exception]` telemetry events
  and keeps the most recent outcome per job in an ETS table. One row per job,
  overwritten on every firing. The dashboard reads from here.

  This is intentionally minimal — only "what happened on the last firing?" plus
  a consecutive-failure counter. Anything more (rolling stats, p95 durations,
  per-job histograms) belongs in PromEx → Grafana, which already has it.
  """

  use GenServer

  require Logger

  @table :edge_admin_local_scheduler_history
  @scheduler EdgeAdmin.LocalScheduler

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the recorded entry for a job, or `nil` if the job has never fired
  since this admin started.

  Entry shape:

      %{
        last_run_at: DateTime.t(),
        last_duration_native: integer(),
        last_outcome: :ok | :error,
        last_error: String.t() | nil,
        consecutive_failures: non_neg_integer()
      }
  """
  def get(job_name) when is_atom(job_name) do
    case :ets.lookup(@table, job_name) do
      [{^job_name, entry}] -> entry
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc """
  Returns all recorded entries as a map keyed by job name.

  Returns `%{}` if the History GenServer has not started yet (e.g. early in
  app boot) or has crashed without yet being restarted by its supervisor.
  """
  def all do
    @table
    |> :ets.tab2list()
    |> Map.new()
  rescue
    ArgumentError -> %{}
  end

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])

    :telemetry.attach_many(
      "edge-admin-local-scheduler-history",
      [
        [:quantum, :job, :stop],
        [:quantum, :job, :exception]
      ],
      &__MODULE__.handle_telemetry/4,
      nil
    )

    Logger.info("LocalScheduler.History started")
    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach("edge-admin-local-scheduler-history")
    :ok
  end

  # ---------------------------------------------------------------------------
  # Telemetry handler — runs in the calling process, must not crash
  # ---------------------------------------------------------------------------

  @doc false
  def handle_telemetry(event, measurements, metadata, _config) do
    if metadata[:scheduler] == @scheduler do
      record(event, measurements, metadata)
    end
  rescue
    e -> Logger.error("History telemetry handler crashed: #{Exception.message(e)}")
  end

  defp record([:quantum, :job, :stop], %{duration: duration}, %{job: job}) do
    upsert(job_name(job), fn _existing ->
      %{
        last_run_at: DateTime.utc_now(),
        last_duration_native: duration,
        last_outcome: :ok,
        last_error: nil,
        consecutive_failures: 0
      }
    end)
  end

  defp record([:quantum, :job, :exception], %{duration: duration}, metadata) do
    %{job: job, kind: kind, reason: reason} = metadata

    upsert(job_name(job), fn existing ->
      previous_failures = (existing && existing.consecutive_failures) || 0

      %{
        last_run_at: DateTime.utc_now(),
        last_duration_native: duration,
        last_outcome: :error,
        last_error: format_error(kind, reason),
        consecutive_failures: previous_failures + 1
      }
    end)
  end

  defp record(_event, _measurements, _metadata), do: :ok

  defp upsert(name, fun) do
    existing =
      case :ets.lookup(@table, name) do
        [{^name, entry}] -> entry
        [] -> nil
      end

    :ets.insert(@table, {name, fun.(existing)})
  end

  defp job_name(%{name: name}), do: name
  defp job_name(name) when is_atom(name), do: name

  defp format_error(kind, reason) do
    String.slice("#{kind}: #{inspect(reason, limit: 5, printable_limit: 200)}", 0, 300)
  end
end
