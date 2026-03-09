# edge_admin/lib/edge_admin/nodes/checks/update_cluster_check.ex
defmodule EdgeAdmin.Nodes.Checks.UpdateClusterCheck do
  @moduledoc """
  Precondition check for cluster update operations.

  Validates that the proposed changes to a cluster are compatible with its current state.
  """

  import Ecto.Query

  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  @doc """
  Checks whether a proposed new node_limit is valid given the cluster's current node count.

  Passes when:
  - `new_limit` is nil (removing the cap)
  - `new_limit` >= current node count (limit accommodates existing nodes)

  Returns an error if the proposed limit would make the cluster permanently over-capacity,
  locking out all future registrations with no way to resolve it short of deleting nodes.
  """
  @spec check(Cluster.t(), integer() | nil) :: :ok | {:error, {:unprocessable, String.t()}}
  def check(_cluster, nil), do: :ok

  def check(%Cluster{id: cluster_id}, new_limit) do
    count = Repo.aggregate(from(n in Node, where: n.cluster_id == ^cluster_id), :count)

    if new_limit >= count do
      :ok
    else
      {:error, {:unprocessable, "node_limit (#{new_limit}) cannot be less than current node count (#{count})"}}
    end
  end
end
