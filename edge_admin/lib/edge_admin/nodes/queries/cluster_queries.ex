# edge_admin/lib/edge_admin/nodes/queries/cluster_queries.ex
defmodule EdgeAdmin.Nodes.Queries.ClusterQueries do
  @moduledoc """
  Reusable Ecto query scopes for clusters.

  These helpers are pure query builders. They do not execute queries or encode
  persistence behavior, which keeps the definition of an active cluster
  consistent across the Nodes context and its workflows/resources.
  """

  import Ecto.Query, warn: false

  alias EdgeAdmin.Nodes.Schemas.Cluster

  @doc "Returns clusters that have not been retired."
  def active(queryable \\ Cluster) do
    from(c in queryable, where: is_nil(c.deleted_at))
  end

  @doc "Returns active clusters matching the given name."
  def active_by_name(queryable \\ Cluster, name) do
    from(c in active(queryable), where: c.name == ^name)
  end

  @doc "Returns active clusters matching the given ID."
  def active_by_id(queryable \\ Cluster, id) do
    from(c in active(queryable), where: c.id == ^id)
  end

  @doc "Restricts a query whose cluster is the second binding to active clusters."
  def active_joined(query) do
    from([_primary, c] in query, where: is_nil(c.deleted_at))
  end
end
