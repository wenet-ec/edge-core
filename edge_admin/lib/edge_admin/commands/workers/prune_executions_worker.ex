# edge_admin/lib/edge_admin/commands/workers/prune_executions_worker.ex
defmodule EdgeAdmin.Commands.Workers.PruneExecutionsWorker do
  @moduledoc """
  Periodic worker that deletes finalised command executions older than
  `EXECUTION_RETENTION_DAYS`.

  The cron entry is always registered; the worker no-ops when
  `EXECUTION_PRUNING_ENABLED` is `false` (the default). This mirrors the
  `cluster_reconciliation_enabled` pattern — keep scheduling unconditional,
  gate execution at the worker.

  Only rows where the execution can no longer receive any updates are deleted
  (see `EdgeAdmin.Commands.prune_executions/1`). In-flight executions
  (`pending`, `sent`) are never touched.

  `max_attempts: 1` — a missed run is recovered by the next cron tick, no
  retry storm needed.
  """

  use Oban.Worker, queue: :execution_pruning, max_attempts: 1

  alias EdgeAdmin.Commands

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if should_run?() do
      run()
    else
      Logger.debug("PruneExecutionsWorker: pruning disabled, skipping")
      :ok
    end
  end

  defp run do
    retention_days = Application.fetch_env!(:edge_admin, :execution_retention_days)

    started_at = System.monotonic_time()
    {:ok, deleted} = Commands.prune_executions(retention_days)
    duration_ms = System.convert_time_unit(System.monotonic_time() - started_at, :native, :millisecond)

    Logger.info("Pruned #{deleted} finalised command execution(s) older than #{retention_days} day(s)")

    :telemetry.execute(
      [:edge_admin, :commands, :pruning],
      %{deleted_count: deleted, duration: duration_ms},
      %{retention_days: retention_days}
    )

    :ok
  end

  defp should_run? do
    Application.get_env(:edge_admin, :execution_pruning_enabled, false)
  end
end
