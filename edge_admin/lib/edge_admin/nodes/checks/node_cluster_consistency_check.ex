# edge_admin/lib/edge_admin/nodes/checks/node_cluster_consistency_check.ex
defmodule EdgeAdmin.Nodes.Checks.NodeClusterConsistencyCheck do
  @moduledoc """
  Validates the denormalized cluster ID stored on an alias.

  Foreign keys prove that the node and cluster exist independently. This
  check verifies that the alias points to the cluster currently owning its node.
  """

  import Ecto.Changeset, only: [add_error: 4, get_field: 2]
  import Ecto.Query, only: [from: 2]

  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  @doc "Ensures an alias cluster matches the cluster currently owning its node."
  @spec check(Ecto.Changeset.t()) :: {:ok, Ecto.Changeset.t()} | {:error, Ecto.Changeset.t()}
  def check(changeset) do
    node_id = get_field(changeset, :node_id)
    cluster_id = get_field(changeset, :cluster_id)

    if is_binary(node_id) and is_binary(cluster_id) do
      case Repo.one(from(n in Node, where: n.id == ^node_id, select: n.cluster_id)) do
        ^cluster_id ->
          {:ok, changeset}

        nil ->
          # The node FK constraint owns the missing-node error.
          {:ok, changeset}

        _different_cluster_id ->
          {:error,
           add_error(
             changeset,
             :cluster_id,
             "must match the node's cluster",
             validation: :node_cluster_consistency
           )}
      end
    else
      # Required-field and type validation remain the schema's responsibility.
      {:ok, changeset}
    end
  end
end
