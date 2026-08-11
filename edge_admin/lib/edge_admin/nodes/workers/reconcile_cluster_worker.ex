# edge_admin/lib/edge_admin/nodes/workers/reconcile_cluster_worker.ex
defmodule EdgeAdmin.Nodes.Workers.ReconcileClusterWorker do
  @moduledoc """
  Oban worker that reconciles a single cluster's state between the DB and Edge VPN.

  Enqueued by ScheduleClusterReconciliationWorker — one job per cluster. Each job:
  1. Recreates a missing network from active DB cluster configuration
  2. Adds missing nodes to the Edge VPN network (DB says yes, Edge VPN says no)
  3. Removes extra managed nodes from the network (Edge VPN says yes, DB says no)
  4. Evicts rogue hosts (unrecognized hosts with no DB record, if EVICT_ROGUE_HOSTS=true)
  5. Cleans up orphaned aliases for nodes no longer in Edge VPN
  6. Deletes orphaned DB records for nodes whose Edge VPN host is gone
  7. Repairs missing/stale alias DNS and cleans up ghost alias DNS

  Retried up to 3 times on failure. Each cluster is independent — a Edge VPN timeout
  on one cluster does not affect reconciliation of others.
  """

  use Oban.Worker,
    queue: :cluster_reconciliation,
    max_attempts: 3,
    unique: [
      period: :infinity,
      states: :incomplete,
      keys: [:cluster_name]
    ]

  alias EdgeAdmin.Nodes

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"cluster_name" => cluster_name}}) do
    start_time = System.monotonic_time(:millisecond)

    case Nodes.reconcile_cluster(cluster_name) do
      {:ok, result} ->
        duration = System.monotonic_time(:millisecond) - start_time

        Logger.info(
          "ReconcileClusterWorker: cluster #{cluster_name} — " <>
            "added=#{result.nodes_added} removed=#{result.nodes_removed} " <>
            "deleted=#{result.nodes_deleted} aliases_cleaned=#{result.aliases_cleaned} " <>
            "aliases_repaired=#{result.aliases_repaired} " <>
            "ghost_aliases_cleaned=#{result.ghost_aliases_cleaned} errors=#{result.errors}"
        )

        outcome = if result.errors > 0, do: :error, else: :ok

        :telemetry.execute(
          [:edge_admin, :nodes, :cluster_reconciliation],
          %{
            duration: duration,
            nodes_added: result.nodes_added,
            nodes_removed: result.nodes_removed,
            nodes_deleted: result.nodes_deleted,
            aliases_cleaned: result.aliases_cleaned,
            aliases_repaired: result.aliases_repaired,
            ghost_aliases_cleaned: result.ghost_aliases_cleaned,
            errors: result.errors
          },
          %{cluster: cluster_name, result: outcome}
        )

        if outcome == :error do
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
