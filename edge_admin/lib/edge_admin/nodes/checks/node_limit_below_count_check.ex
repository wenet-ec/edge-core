# edge_admin/lib/edge_admin/nodes/checks/node_limit_below_count_check.ex
defmodule EdgeAdmin.Nodes.Checks.NodeLimitBelowCountCheck do
  @moduledoc """
  Checks that a proposed node_limit is not below the cluster's current node count.

  Prevents setting a limit that would make the cluster permanently over-capacity,
  locking out all future registrations with no way to resolve it short of deleting nodes.
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
  @spec check(Cluster.t(), integer() | nil) :: :ok | {:error, Ecto.Changeset.t()}
  def check(_cluster, nil), do: :ok

  def check(%Cluster{id: cluster_id} = cluster, new_limit) do
    count = Repo.aggregate(from(n in Node, where: n.cluster_id == ^cluster_id), :count)

    if new_limit >= count do
      :ok
    else
      changeset =
        cluster
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:node_limit, "cannot be less than current node count (%{count})",
          count: count,
          validation: :node_limit_below_count
        )

      {:error, changeset}
    end
  end
end
