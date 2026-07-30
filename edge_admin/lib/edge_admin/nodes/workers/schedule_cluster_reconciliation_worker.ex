# edge_admin/lib/edge_admin/nodes/workers/schedule_cluster_reconciliation_worker.ex
defmodule EdgeAdmin.Nodes.Workers.ScheduleClusterReconciliationWorker do
  @moduledoc """
  Oban worker that fans out per-cluster maintenance jobs on a cron schedule.

  Runs every 6 hours (configurable via CLUSTER_RECONCILIATION_SCHEDULE) and asks the
  Nodes context to enqueue one maintenance job per cluster: active clusters receive a
  ReconcileClusterWorker and retired clusters receive a DeleteClusterWorker.

  Skips enqueueing if the system is in degraded mode or reconciliation is disabled.
  """

  use Oban.Worker,
    queue: :cluster_reconciliation,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: :incomplete
    ]

  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.Nodes

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cond do
      Metadata.degraded?() ->
        Logger.info("ScheduleClusterReconciliationWorker: skipped — system in degraded mode")
        {:discard, "skipped during degraded mode"}

      not should_run?() ->
        Logger.info("ScheduleClusterReconciliationWorker: skipped — reconciliation disabled")
        :ok

      true ->
        Nodes.enqueue_cluster_reconciliation()
    end
  end

  defp should_run? do
    Application.get_env(:edge_admin, :cluster_reconciliation_enabled, true)
  end
end
