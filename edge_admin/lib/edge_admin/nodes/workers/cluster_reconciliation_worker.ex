# edge_admin/lib/edge_admin/nodes/workers/cluster_reconciliation_worker.ex
defmodule EdgeAdmin.Nodes.Workers.ClusterReconciliationWorker do
  @moduledoc """
  Oban worker that periodically reconciles clusters and node membership between database and Netmaker.

  This worker:
  1. Queries all clusters and their nodes from the database (source of truth)
  2. Queries Netmaker networks to see which hosts are actually in each network
  3. Adds missing edge nodes to networks (DB says yes, Netmaker says no)
  4. Removes extra edge nodes from networks (Netmaker says yes, DB says no)
  5. Cleans up orphaned clusters (exist in DB but network doesn't exist in Netmaker)
  6. Cleans up ghost aliases (exist in DB but DNS doesn't exist in Netmaker)

  Only manages edge nodes (nodes with DB records). Admin nodes and staff machines are untouched.

  Handles inconsistencies that occur when:
  - Create/delete operations succeed in DB but fail in Netmaker
  - Cluster migration API calls fail mid-operation
  - Network issues prevent Netmaker sync
  - Manual changes made directly in Netmaker

  Delegates to EdgeAdmin.Nodes.reconcile_clusters/0 for the actual reconciliation logic.
  Processes all clusters in batches of 500.

  Runs on a configurable schedule (default: every 6 hours).
  """

  use Oban.Worker,
    queue: :cluster_reconciliation,
    max_attempts: 3,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.Nodes

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cond do
      Metadata.degraded?() ->
        Logger.info("Cluster reconciliation skipped - system in degraded mode")
        {:discard, "skipped during degraded mode"}

      not should_run?() ->
        Logger.info("Cluster reconciliation is disabled, skipping")
        {:ok, %{clusters_processed: 0, skipped: true}}

      true ->
        Logger.info("Starting cluster reconciliation")

        result = Nodes.reconcile_clusters()

        Logger.info(
          "Cluster reconciliation complete: #{result.clusters_processed} clusters processed, " <>
            "#{result.nodes_added} nodes added, #{result.nodes_removed} nodes removed, " <>
            "#{result.nodes_deleted} nodes deleted, #{result.clusters_deleted} clusters deleted, " <>
            "#{result.aliases_cleaned} aliases cleaned, #{result.ghost_aliases_cleaned} ghost aliases cleaned, " <>
            "#{result.errors} errors"
        )

        {:ok, result}
    end
  end

  defp should_run? do
    Application.get_env(:edge_admin, :cluster_reconciliation_enabled, true)
  end
end
