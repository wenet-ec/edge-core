# edge_admin/lib/edge_admin/nodes/workers/reconcile_cluster_worker.ex
defmodule EdgeAdmin.Nodes.Workers.ReconcileClusterWorker do
  @moduledoc """
  Oban worker that reconciles a single cluster's state between the DB and Edge VPN.

  Each job repairs missing or stale VPN networks, memberships, and alias DNS,
  and removes managed resources that no longer have active database records.
  Clusters are reconciled independently and failed attempts are retried.
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
