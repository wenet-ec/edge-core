# edge_admin/lib/edge_admin/nodes/checks/node_limit_check.ex
defmodule EdgeAdmin.Nodes.Checks.NodeLimitCheck do
  @moduledoc """
  Precondition check for node registration and cluster transfer.

  Passes when the cluster has no node limit or the current node count is below it.
  """

  import Ecto.Query

  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  @spec check(Cluster.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%Cluster{node_limit: nil}), do: :ok

  def check(%Cluster{id: cluster_id, node_limit: limit}) do
    count = Repo.aggregate(from(n in Node, where: n.cluster_id == ^cluster_id), :count)

    if count < limit do
      :ok
    else
      {:error, {:conflict, "cluster has reached its node limit of #{limit}"}}
    end
  end
end
