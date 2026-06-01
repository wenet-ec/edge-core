# edge_admin/lib/edge_admin/nodes/workers/schedule_cluster_reconciliation_worker.ex
defmodule EdgeAdmin.Nodes.Workers.ScheduleClusterReconciliationWorker do
  @moduledoc """
  Oban worker that fans out per-cluster reconciliation jobs on a cron schedule.

  Runs every 6 hours (configurable via CLUSTER_RECONCILIATION_SCHEDULE). Paginates
  all clusters from the DB and enqueues one ReconcileClusterWorker job per cluster.
  Each job independently reconciles that cluster's state between the DB and Netmaker.

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
  alias EdgeAdmin.Nodes.Workers.ReconcileClusterWorker

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
        enqueue_all_clusters()
    end
  end

  defp enqueue_all_clusters(page \\ 1, total \\ 0) do
    {:ok, {clusters, meta}} = Nodes.list_clusters(%{"page_size" => "500", "page" => to_string(page)})

    count =
      Enum.reduce(clusters, 0, fn cluster, acc ->
        case Oban.insert(ReconcileClusterWorker.new(%{"cluster_name" => cluster.name})) do
          {:ok, _job} ->
            acc + 1

          {:error, reason} ->
            Logger.warning(
              "ScheduleClusterReconciliationWorker: failed to enqueue cluster #{cluster.name}: #{inspect(reason)}"
            )

            acc
        end
      end)

    if meta.has_next_page? do
      enqueue_all_clusters(page + 1, total + count)
    else
      Logger.info("ScheduleClusterReconciliationWorker: enqueued #{total + count} cluster reconciliation jobs")
      :ok
    end
  end

  defp should_run? do
    Application.get_env(:edge_admin, :cluster_reconciliation_enabled, true)
  end
end
