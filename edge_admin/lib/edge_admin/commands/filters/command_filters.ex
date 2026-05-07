# edge_admin/lib/edge_admin/commands/filters/command_filters.ex
defmodule EdgeAdmin.Commands.Filters.CommandFilters do
  @moduledoc """
  Ecto query filter helpers for the `commands` table.

  Pure query builders — take a query plus parsed Flop filters, return a query.
  No Repo calls, no side effects.
  """

  import Ecto.Query, warn: false

  @doc """
  Applies `has_timeout` virtual boolean filter — `true` matches commands with
  a non-null `timeout`.
  """
  def apply_has_timeout(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_has_timeout_one(acc, filter) end)
  end

  defp apply_has_timeout_one(query, %{op: :==, value: v}) when v in [true, "true"] do
    from(c in query, where: not is_nil(c.timeout))
  end

  defp apply_has_timeout_one(query, %{op: :==, value: v}) when v in [false, "false"] do
    from(c in query, where: is_nil(c.timeout))
  end

  defp apply_has_timeout_one(query, _), do: query

  @doc """
  Applies `has_expired_at` virtual boolean filter — `true` matches commands
  with a non-null `expired_at` (regardless of whether the timestamp is in the past).
  """
  def apply_has_expired_at(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_has_expired_at_one(acc, filter) end)
  end

  defp apply_has_expired_at_one(query, %{op: :==, value: v}) when v in [true, "true"] do
    from(c in query, where: not is_nil(c.expired_at))
  end

  defp apply_has_expired_at_one(query, %{op: :==, value: v}) when v in [false, "false"] do
    from(c in query, where: is_nil(c.expired_at))
  end

  defp apply_has_expired_at_one(query, _), do: query
end
