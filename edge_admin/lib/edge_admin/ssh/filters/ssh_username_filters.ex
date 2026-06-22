# edge_admin/lib/edge_admin/ssh/filters/ssh_username_filters.ex
defmodule EdgeAdmin.Ssh.Filters.SshUsernameFilters do
  @moduledoc """
  Ecto query filter helpers for the `ssh_usernames` table.

  Pure query builders. The `apply_cluster_name/2` helper assumes the query has
  node and cluster joined as the second and third bindings — see
  `EdgeAdmin.Ssh.list_ssh_usernames/1`.
  """

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  @doc """
  Applies `has_password` virtual boolean filter — true/false matches
  `password_hash IS [NOT] NULL`.
  """
  def apply_has_password(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_has_password_one(acc, filter) end)
  end

  defp apply_has_password_one(query, %{op: :==, value: true}) do
    from(u in query, where: not is_nil(u.password_hash))
  end

  defp apply_has_password_one(query, %{op: :==, value: false}) do
    from(u in query, where: is_nil(u.password_hash))
  end

  defp apply_has_password_one(query, _), do: query

  @doc """
  Applies `cluster_name` filter on a query joined as `[u, n, c]`.
  Filters by the username's node's cluster name.
  """
  def apply_cluster_name(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_cluster_name_one(acc, filter) end)
  end

  defp apply_cluster_name_one(query, %{op: :==, value: value}) when is_binary(value) do
    from([_u, _n, c] in query, where: c.name == ^value)
  end

  defp apply_cluster_name_one(query, %{op: :ilike, value: value}) when is_binary(value) do
    from([_u, _n, c] in query, where: case_insensitive_like(c.name, ^value))
  end

  defp apply_cluster_name_one(query, %{op: :in, value: values}) when is_list(values) do
    from([_u, _n, c] in query, where: c.name in ^values)
  end

  defp apply_cluster_name_one(query, _), do: query

  @doc """
  Applies `node_id__in` IN filter on a query joined as `[u, n, c]`.
  """
  def apply_node_ids(query, []), do: query

  def apply_node_ids(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_node_ids_one(acc, filter) end)
  end

  defp apply_node_ids_one(query, %{op: :in, value: values}) when is_list(values) do
    from([_u, n] in query, where: n.id in ^values)
  end

  defp apply_node_ids_one(query, %{op: :==, value: value}) when is_binary(value) do
    from([_u, n] in query, where: n.id == ^value)
  end

  defp apply_node_ids_one(query, _), do: query

  @doc """
  Applies `key_name` filter by joining into `ssh_public_keys` (has_many side).
  Supports exact match, ilike wildcard, and exact IN. Applies `distinct` to
  avoid duplicate username rows when multiple keys match.
  """
  def apply_key_name(query, []), do: query

  def apply_key_name(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_key_name_one(acc, filter) end)
  end

  defp apply_key_name_one(query, %{op: :==, value: value}) when is_binary(value) do
    from(u in query,
      join: k in assoc(u, :ssh_public_keys),
      where: k.key_name == ^value,
      distinct: true
    )
  end

  defp apply_key_name_one(query, %{op: :ilike, value: value}) when is_binary(value) do
    from(u in query,
      join: k in assoc(u, :ssh_public_keys),
      where: case_insensitive_like(k.key_name, ^value),
      distinct: true
    )
  end

  defp apply_key_name_one(query, %{op: :in, value: values}) when is_list(values) do
    from(u in query,
      join: k in assoc(u, :ssh_public_keys),
      where: k.key_name in ^values,
      distinct: true
    )
  end

  defp apply_key_name_one(query, _), do: query
end
