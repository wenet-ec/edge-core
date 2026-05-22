# edge_admin/lib/edge_admin/nodes/filters/enrollment_key_filters.ex
defmodule EdgeAdmin.Nodes.Filters.EnrollmentKeyFilters do
  @moduledoc """
  Ecto query filter helpers for the `enrollment_keys` table.

  Pure query builders for the virtual booleans Flop can't express directly:
  `is_unlimited`, `is_spent`, `is_expired`, `is_never_used`, `has_expiry`, `has_name`.
  """

  import Ecto.Query, warn: false

  @doc """
  Applies `is_unlimited` filter — `true` matches keys with no `uses_remaining` cap.
  """
  def apply_is_unlimited(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_is_unlimited_one(acc, filter) end)
  end

  defp apply_is_unlimited_one(query, %{op: :==, value: v}) when v in [true, "true"] do
    from(k in query, where: is_nil(k.uses_remaining))
  end

  defp apply_is_unlimited_one(query, %{op: :==, value: v}) when v in [false, "false"] do
    from(k in query, where: not is_nil(k.uses_remaining))
  end

  defp apply_is_unlimited_one(query, _), do: query

  @doc """
  Applies `is_spent` filter — `true` matches keys with `uses_remaining == 0`.
  """
  def apply_is_spent(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_is_spent_one(acc, filter) end)
  end

  defp apply_is_spent_one(query, %{op: :==, value: v}) when v in [true, "true"] do
    from(k in query, where: k.uses_remaining == 0)
  end

  defp apply_is_spent_one(query, %{op: :==, value: v}) when v in [false, "false"] do
    from(k in query, where: k.uses_remaining != 0 or is_nil(k.uses_remaining))
  end

  defp apply_is_spent_one(query, _), do: query

  @doc """
  Applies `is_expired` filter — compares `expires_at` to now at query time.
  """
  def apply_is_expired(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_is_expired_one(acc, filter) end)
  end

  defp apply_is_expired_one(query, %{op: :==, value: v}) when v in [true, "true"] do
    now = DateTime.utc_now()
    from(k in query, where: not is_nil(k.expires_at) and k.expires_at < ^now)
  end

  defp apply_is_expired_one(query, %{op: :==, value: v}) when v in [false, "false"] do
    now = DateTime.utc_now()
    from(k in query, where: is_nil(k.expires_at) or k.expires_at >= ^now)
  end

  defp apply_is_expired_one(query, _), do: query

  @doc """
  Applies `is_never_used` filter — `true` matches keys with no `last_used_at`.
  """
  def apply_is_never_used(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_is_never_used_one(acc, filter) end)
  end

  defp apply_is_never_used_one(query, %{op: :==, value: v}) when v in [true, "true"] do
    from(k in query, where: is_nil(k.last_used_at))
  end

  defp apply_is_never_used_one(query, %{op: :==, value: v}) when v in [false, "false"] do
    from(k in query, where: not is_nil(k.last_used_at))
  end

  defp apply_is_never_used_one(query, _), do: query

  @doc """
  Applies `has_expiry` filter — `true` matches keys with `expires_at` set
  (regardless of whether the timestamp is in the past).
  """
  def apply_has_expiry(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_has_expiry_one(acc, filter) end)
  end

  defp apply_has_expiry_one(query, %{op: :==, value: v}) when v in [true, "true"] do
    from(k in query, where: not is_nil(k.expires_at))
  end

  defp apply_has_expiry_one(query, %{op: :==, value: v}) when v in [false, "false"] do
    from(k in query, where: is_nil(k.expires_at))
  end

  defp apply_has_expiry_one(query, _), do: query

  @doc """
  Applies `has_name` filter — `true` matches keys with a `name` set
  (any non-null label, including the empty string if one were ever stored).
  """
  def apply_has_name(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_has_name_one(acc, filter) end)
  end

  defp apply_has_name_one(query, %{op: :==, value: v}) when v in [true, "true"] do
    from(k in query, where: not is_nil(k.name))
  end

  defp apply_has_name_one(query, %{op: :==, value: v}) when v in [false, "false"] do
    from(k in query, where: is_nil(k.name))
  end

  defp apply_has_name_one(query, _), do: query

  @doc """
  Conditionally applies a filter function only when the filter list is non-empty.
  Used in pipe chains where each filter group is optional.
  """
  def apply_maybe(query, nil, _fun), do: query
  def apply_maybe(query, [], _fun), do: query
  def apply_maybe(query, filters, fun), do: fun.(query, filters)
end
