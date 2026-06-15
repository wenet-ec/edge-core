# edge_admin/lib/edge_admin/nodes/filters/cluster_filters.ex
defmodule EdgeAdmin.Nodes.Filters.ClusterFilters do
  @moduledoc """
  Ecto query filter helpers for the `clusters` table and queries that join clusters.

  These helpers are pure query builders — they take a query plus a list of parsed
  Flop filters (`%{op: ..., value: ..., field: ...}`) and return a query. No Repo
  calls, no side effects. Used by `EdgeAdmin.Nodes` listing functions that need to
  apply virtual / wildcard / aggregate filters that Flop can't express directly.
  """

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  @doc """
  Applies `has_node_limit` virtual boolean filters to a Cluster query.

  Maps `true`/`false` to `node_limit IS NOT NULL` / `IS NULL`.
  """
  def apply_has_node_limit(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_has_node_limit_one(acc, filter) end)
  end

  defp apply_has_node_limit_one(query, %{op: :==, value: v}) when v in [true, "true"] do
    from(c in query, where: not is_nil(c.node_limit))
  end

  defp apply_has_node_limit_one(query, %{op: :==, value: v}) when v in [false, "false"] do
    from(c in query, where: is_nil(c.node_limit))
  end

  defp apply_has_node_limit_one(query, _), do: query

  @doc """
  Applies ilike filters for string fields directly via Ecto, bypassing Flop's
  `add_wildcard` (which escapes `%` and wraps values in `%..%`, breaking
  user-supplied patterns like `prod*`).
  """
  def apply_ilike(query, filters) do
    Enum.reduce(filters, query, fn %{field: field, value: value}, acc ->
      from(c in acc, where: case_insensitive_like(field(c, ^field), ^value))
    end)
  end

  @doc """
  Applies `node_count` aggregate filters using a HAVING clause.

  Caller must have set up the query with a left_join to nodes and group_by
  on cluster id (see `EdgeAdmin.Nodes.list_clusters/1`).
  """
  def apply_node_count(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_node_count_one(acc, filter) end)
  end

  defp apply_node_count_one(query, %{op: :>=, value: value}) when is_integer(value),
    do: from([c, n] in query, having: count(n.id) >= ^value)

  defp apply_node_count_one(query, %{op: :>=, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) >= ^num)
      _ -> query
    end
  end

  defp apply_node_count_one(query, %{op: :>, value: value}) when is_integer(value),
    do: from([c, n] in query, having: count(n.id) > ^value)

  defp apply_node_count_one(query, %{op: :>, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) > ^num)
      _ -> query
    end
  end

  defp apply_node_count_one(query, %{op: :<=, value: value}) when is_integer(value),
    do: from([c, n] in query, having: count(n.id) <= ^value)

  defp apply_node_count_one(query, %{op: :<=, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) <= ^num)
      _ -> query
    end
  end

  defp apply_node_count_one(query, %{op: :<, value: value}) when is_integer(value),
    do: from([c, n] in query, having: count(n.id) < ^value)

  defp apply_node_count_one(query, %{op: :<, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) < ^num)
      _ -> query
    end
  end

  defp apply_node_count_one(query, %{op: :==, value: value}) when is_integer(value),
    do: from([c, n] in query, having: count(n.id) == ^value)

  defp apply_node_count_one(query, %{op: :==, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) == ^num)
      _ -> query
    end
  end

  defp apply_node_count_one(query, %{op: :!=, value: value}) when is_integer(value),
    do: from([c, n] in query, having: count(n.id) != ^value)

  defp apply_node_count_one(query, %{op: :!=, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) != ^num)
      _ -> query
    end
  end

  defp apply_node_count_one(query, _), do: query

  @doc """
  Applies `cluster_name` filters on a query that has cluster joined as the
  second binding (i.e. `[primary, c]`). Used by node, alias, and enrollment-key
  listings that join cluster for filtering and preload.
  """
  def apply_name(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_name_one(acc, filter) end)
  end

  defp apply_name_one(query, %{op: :==, value: value}) when is_binary(value) do
    from([_main, c] in query, where: c.name == ^value)
  end

  defp apply_name_one(query, %{op: :ilike, value: value}) when is_binary(value) do
    from([_main, c] in query, where: case_insensitive_like(c.name, ^value))
  end

  defp apply_name_one(query, %{op: :in, value: values}) when is_list(values) do
    from([_main, c] in query, where: c.name in ^values)
  end

  defp apply_name_one(query, _), do: query

  @doc """
  Applies `cluster_names` IN filter directly on the `clusters` table (first binding).
  Used by `list_clusters/1` where the cluster is the primary binding.
  """
  def apply_names(query, []), do: query

  def apply_names(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_names_one(acc, filter) end)
  end

  defp apply_names_one(query, %{op: :in, value: values}) when is_list(values) do
    from(c in query, where: c.name in ^values)
  end

  defp apply_names_one(query, %{op: :==, value: value}) when is_binary(value) do
    from(c in query, where: c.name == ^value)
  end

  defp apply_names_one(query, _), do: query

  @doc """
  Applies `node_ids` IN filter on `list_clusters` — joins nodes and filters
  clusters that contain any of the given node IDs. Applies `distinct` to
  avoid duplicate cluster rows when multiple node IDs land in the same cluster.
  """
  def apply_node_ids_on_clusters(query, []), do: query

  def apply_node_ids_on_clusters(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_node_ids_on_clusters_one(acc, filter) end)
  end

  defp apply_node_ids_on_clusters_one(query, %{op: :in, value: values}) when is_list(values) do
    from(c in query,
      join: n in assoc(c, :nodes),
      where: n.id in ^values,
      distinct: true
    )
  end

  defp apply_node_ids_on_clusters_one(query, %{op: :==, value: value}) when is_binary(value) do
    from(c in query,
      join: n in assoc(c, :nodes),
      where: n.id == ^value,
      distinct: true
    )
  end

  defp apply_node_ids_on_clusters_one(query, _), do: query
end
