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
end
