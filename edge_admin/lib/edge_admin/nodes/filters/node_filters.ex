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

  @doc "Applies `enrollment_key_id__in` to nodes with matching enrollment-key provenance."
  def apply_enrollment_key_ids(query, []), do: query

  def apply_enrollment_key_ids(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_enrollment_key_ids_one(acc, filter) end)
  end

  defp apply_enrollment_key_ids_one(query, %{op: :in, value: values}) when is_list(values) do
    from(n in query, where: n.enrollment_key_id in ^values)
  end

  defp apply_enrollment_key_ids_one(query, %{op: :==, value: value}) when is_binary(value) do
    from(n in query, where: n.enrollment_key_id == ^value)
  end

  defp apply_enrollment_key_ids_one(query, _), do: query

  @doc "Applies `has_enrollment_key` as an enrollment-key association presence filter."
  def apply_has_enrollment_key(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_has_enrollment_key_one(acc, filter) end)
  end

  defp apply_has_enrollment_key_one(query, %{op: :==, value: true}) do
    from(n in query, where: not is_nil(n.enrollment_key_id))
  end

  defp apply_has_enrollment_key_one(query, %{op: :==, value: false}) do
    from(n in query, where: is_nil(n.enrollment_key_id))
  end

  defp apply_has_enrollment_key_one(query, _), do: query
end
