# edge_admin/lib/edge_admin/nodes/workers/reconcile_cluster_worker.ex
defmodule EdgeAdmin.Nodes.Workers.ReconcileClusterWorker do
  @moduledoc """
  Oban worker that reconciles a single cluster's state between the DB and Netmaker.

  Enqueued by ScheduleClusterReconciliationWorker — one job per cluster. Each job:
  1. Adds missing nodes to the Netmaker network (DB says yes, Netmaker says no)
  2. Removes extra managed nodes from the network (Netmaker says yes, DB says no)
  3. Evicts rogue hosts (unrecognized hosts with no DB record, if EVICT_ROGUE_HOSTS=true)
  4. Cleans up orphaned aliases for nodes no longer in Netmaker
  5. Deletes orphaned DB records for nodes whose Netmaker host is gone
  6. Deletes the cluster from DB if its Netmaker network no longer exists
  7. Cleans up ghost aliases (DB aliases with no corresponding Netmaker DNS entry)

  Retried up to 3 times on failure. Each cluster is independent — a Netmaker timeout
  on one cluster does not affect reconciliation of others.
  """

  use Oban.Worker,
    queue: :cluster_reconciliation,
    max_attempts: 3,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable],
      keys: [:cluster_name]
    ]

  alias EdgeAdmin.Nodes

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"cluster_name" => cluster_name}}) do
    case Nodes.get_cluster(cluster_name) do
      {:ok, cluster} ->
        result = Nodes.reconcile_cluster(cluster)

        Logger.info(
          "ReconcileClusterWorker: cluster #{cluster.name} — " <>
            "added=#{result.nodes_added} removed=#{result.nodes_removed} " <>
            "deleted=#{result.nodes_deleted} aliases_cleaned=#{result.aliases_cleaned} " <>
            "ghost_aliases_cleaned=#{result.ghost_aliases_cleaned} errors=#{result.errors}"
        )

        if result.errors > 0 do
          {:error, "reconciliation completed with #{result.errors} error(s)"}
        else
          :ok
        end

      {:error, :not_found} ->
        Logger.info("ReconcileClusterWorker: cluster #{cluster_name} no longer exists, skipping")
        :ok
    end
  end
end
