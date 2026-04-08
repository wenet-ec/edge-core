# edge_admin/lib/edge_admin/nodes/checks/cluster_not_empty_check.ex
defmodule EdgeAdmin.Nodes.Checks.ClusterNotEmptyCheck do
  @moduledoc """
  Checks that a cluster has no nodes before allowing deletion.

  Prevents cascading deletion of active nodes.
  """

  import Ecto.Query

  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  @spec check(Cluster.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%Cluster{id: cluster_id}) do
    count = Repo.one(from(n in Node, where: n.cluster_id == ^cluster_id, select: count(n.id)))

    if count == 0 do
      :ok
    else
      {:error, {:conflict, "cannot delete cluster with #{count} node(s) - remove all nodes first"}}
    end
  end
end
