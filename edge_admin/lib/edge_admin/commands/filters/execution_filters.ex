# edge_admin/lib/edge_admin/commands/filters/execution_filters.ex
defmodule EdgeAdmin.Commands.Filters.ExecutionFilters do
  @moduledoc """
  Ecto query filter helpers for the `command_executions` table.

  Pure query builders. The `apply_cluster_name/2` and `apply_has_cluster/2`
  helpers assume the query has node and cluster joined as the second and third
  bindings — see `EdgeAdmin.Commands.list_command_executions/1`.
  """

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  @doc """
  Applies `cluster_name` filter on a query joined as `[ce, n, c]`.
  Filters by the node's cluster name.
  """
  def apply_cluster_name(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_cluster_name_one(acc, filter) end)
  end

  defp apply_cluster_name_one(query, %{op: :==, value: value}) when is_binary(value) do
    from([ce, n, c] in query, where: c.name == ^value)
  end

  defp apply_cluster_name_one(query, %{op: :ilike, value: value}) when is_binary(value) do
    from([ce, n, c] in query, where: case_insensitive_like(c.name, ^value))
  end

  defp apply_cluster_name_one(query, %{op: :in, value: values}) when is_list(values) do
    from([ce, n, c] in query, where: c.name in ^values)
  end

  defp apply_cluster_name_one(query, _), do: query

  @doc """
  Applies `command_ids` IN filter directly on `ce.command_id`.
  """
  def apply_command_ids(query, []), do: query

  def apply_command_ids(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_command_ids_one(acc, filter) end)
  end

  defp apply_command_ids_one(query, %{op: :in, value: values}) when is_list(values) do
    from(ce in query, where: ce.command_id in ^values)
  end

  defp apply_command_ids_one(query, %{op: :==, value: value}) when is_binary(value) do
    from(ce in query, where: ce.command_id == ^value)
  end

  defp apply_command_ids_one(query, _), do: query

  @doc """
  Applies `node_ids` IN filter on a query joined as `[ce, n, c]`.
  """
  def apply_node_ids(query, []), do: query

  def apply_node_ids(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_node_ids_one(acc, filter) end)
  end

  defp apply_node_ids_one(query, %{op: :in, value: values}) when is_list(values) do
    from([ce, n] in query, where: n.id in ^values)
  end

  defp apply_node_ids_one(query, %{op: :==, value: value}) when is_binary(value) do
    from([ce, n] in query, where: n.id == ^value)
  end

  defp apply_node_ids_one(query, _), do: query

  @doc """
  Applies `has_cluster` virtual boolean filter — true/false matches `cluster_id IS [NOT] NULL`.
  Assumes the same `[ce, _n, _c]` binding shape as `apply_cluster_name/2`.
  """
  def apply_has_cluster(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_has_cluster_one(acc, filter) end)
  end

  defp apply_has_cluster_one(query, %{op: :==, value: "true"}) do
    from([ce, _n, _c] in query, where: not is_nil(ce.cluster_id))
  end

  defp apply_has_cluster_one(query, %{op: :==, value: "false"}) do
    from([ce, _n, _c] in query, where: is_nil(ce.cluster_id))
  end

  defp apply_has_cluster_one(query, %{op: :==, value: true}) do
    from([ce, _n, _c] in query, where: not is_nil(ce.cluster_id))
  end

  defp apply_has_cluster_one(query, %{op: :==, value: false}) do
    from([ce, _n, _c] in query, where: is_nil(ce.cluster_id))
  end

  defp apply_has_cluster_one(query, _), do: query

  @doc """
  Applies `has_output` virtual boolean filter — true matches executions whose
  `output` column is non-null.
  """
  def apply_has_output(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_has_output_one(acc, filter) end)
  end

  defp apply_has_output_one(query, %{op: :==, value: v}) when v in [true, "true"] do
    from(ce in query, where: not is_nil(ce.output))
  end

  defp apply_has_output_one(query, %{op: :==, value: v}) when v in [false, "false"] do
    from(ce in query, where: is_nil(ce.output))
  end

  defp apply_has_output_one(query, _), do: query
end
