# edge_admin/lib/edge_admin/nodes/persistence.ex
defmodule EdgeAdmin.Nodes.Persistence do
  @moduledoc """
  Database persistence helpers for Nodes workflows.

  This module owns adapter-aware row locking while the cluster query module
  remains a pure query-builder module.
  """

  import Ecto.Query, warn: false

  alias Ecto.Adapters.Postgres
  alias EdgeAdmin.Nodes.Queries.ClusterQueries
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  @doc "Returns and locks an active cluster by name when the adapter supports row locks."
  def lock_active_cluster(name) do
    name
    |> ClusterQueries.active_by_name()
    |> lock_for_update()
    |> Repo.one()
  end

  @doc "Returns and locks a node by ID when the adapter supports row locks."
  def lock_node(node_id) do
    from(n in Node, where: n.id == ^node_id)
    |> lock_for_update()
    |> Repo.one()
  end

  defp lock_for_update(query) do
    case Repo.__adapter__() do
      Postgres -> from(row in query, lock: "FOR UPDATE")
      _ -> query
    end
  end
end
