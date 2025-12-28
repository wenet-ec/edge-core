# edge_admin/lib/edge_admin/nodes/rules/deletion_rules.ex
defmodule EdgeAdmin.Nodes.Rules.DeletionRules do
  @moduledoc """
  Business rules for cluster deletion.

  These rules enforce domain constraints to maintain data integrity
  and prevent deletion of non-empty clusters.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  @doc """
  Validates that a cluster can be deleted.

  Only empty clusters (with no nodes) can be deleted.
  This prevents cascading deletion of active nodes.

  ## Returns
  - `:ok` - Cluster can be deleted
  - `{:error, changeset}` - Cluster cannot be deleted (has nodes)
  """
  def validate_cluster_deletion(%Cluster{id: cluster_id} = cluster) do
    node_count = Repo.one(from(n in Node, where: n.cluster_id == ^cluster_id, select: count(n.id)))

    if node_count == 0 do
      :ok
    else
      changeset =
        cluster
        |> change()
        |> add_error(
          :base,
          "cannot delete cluster with #{node_count} node(s) - remove all nodes first"
        )

      {:error, changeset}
    end
  end
end
