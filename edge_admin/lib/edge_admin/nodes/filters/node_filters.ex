# edge_admin/lib/edge_admin/nodes/filters/node_filters.ex
defmodule EdgeAdmin.Nodes.Filters.NodeFilters do
  @moduledoc """
  Ecto query filter helpers for the `nodes` table.

  Pure query builders. See `EdgeAdmin.Nodes.Filters.ClusterFilters` for the
  rationale behind hand-rolled ilike (Flop's `:ilike` mangles user-supplied
  wildcard patterns).
  """

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  @doc """
  Applies ilike filters for node string fields directly via Ecto, bypassing
  Flop's `add_wildcard`.
  """
  def apply_ilike(query, filters) do
    Enum.reduce(filters, query, fn %{field: field, value: value}, acc ->
      from(n in acc, where: case_insensitive_like(field(n, ^field), ^value))
    end)
  end

  @doc """
  Applies `node_id__in` IN filter directly on the `nodes` table.
  """
  def apply_node_ids(query, []), do: query

  def apply_node_ids(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_node_ids_one(acc, filter) end)
  end

  defp apply_node_ids_one(query, %{op: :in, value: values}) when is_list(values) do
    from(n in query, where: n.id in ^values)
  end

  defp apply_node_ids_one(query, %{op: :==, value: value}) when is_binary(value) do
    from(n in query, where: n.id == ^value)
  end

  defp apply_node_ids_one(query, _), do: query
end
