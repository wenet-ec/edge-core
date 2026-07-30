# edge_admin/lib/edge_admin/nodes/workers/delete_cluster_worker.ex
defmodule EdgeAdmin.Nodes.Workers.DeleteClusterWorker do
  @moduledoc """
  Oban worker that completes deletion of one retired cluster.
  """

  use Oban.Worker,
    queue: :cluster_deletion,
    max_attempts: 3,
    unique: [
      period: :infinity,
      states: :incomplete,
      keys: [:cluster_name]
    ]

  alias EdgeAdmin.Nodes

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"cluster_name" => cluster_name, "cluster_id" => cluster_id}}) do
    case Nodes.complete_cluster_deletion(cluster_name, cluster_id) do
      :ok -> :ok
      {:error, :not_retired} -> {:discard, "cluster is active"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
