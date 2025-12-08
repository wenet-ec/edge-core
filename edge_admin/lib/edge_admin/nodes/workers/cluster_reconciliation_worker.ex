# lib/edge_admin/nodes/workers/cluster_reconciliation_worker.ex
defmodule EdgeAdmin.Nodes.Workers.ClusterReconciliationWorker do
  @moduledoc """
  Oban worker that periodically reconciles cluster node membership between database and Netmaker.

  This worker:
  1. Queries all clusters and their nodes from the database (source of truth)
  2. Queries Netmaker networks to see which hosts are actually in each network
  3. Adds missing edge nodes to networks (DB says yes, Netmaker says no)
  4. Removes extra edge nodes from networks (Netmaker says yes, DB says no)

  Only manages edge nodes (nodes with DB records). Admin nodes and staff machines are untouched.

  Handles inconsistencies that occur when:
  - Cluster migration API calls fail mid-operation
  - Network issues prevent Netmaker sync
  - Manual changes made directly in Netmaker

  Delegates to EdgeAdmin.Nodes.reconcile_cluster_nodes/0 for the actual reconciliation logic.

  Runs on a configurable schedule (default: every 6 hours).
  """

  use Oban.Worker,
    queue: :cluster_reconciliation,
    max_attempts: 3,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias EdgeAdmin.Nodes

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # Check if reconciliation is enabled
    if Application.get_env(:edge_admin, :cluster_reconciliation_enabled, true) do
      Logger.info("Starting cluster reconciliation")

      result = Nodes.reconcile_cluster_nodes()

      Logger.info(
        "Cluster reconciliation complete: #{result.clusters_processed} clusters processed, " <>
          "#{result.nodes_added} nodes added, #{result.nodes_removed} nodes removed, " <>
          "#{result.errors} errors"
      )

      {:ok, result}
    else
      Logger.info("Cluster reconciliation is disabled, skipping")
      {:ok, %{clusters_processed: 0, skipped: true}}
    end
  end
end
