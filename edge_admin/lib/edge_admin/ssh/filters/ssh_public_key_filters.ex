# edge_admin/lib/edge_admin/ssh/filters/ssh_public_key_filters.ex
defmodule EdgeAdmin.Ssh.Filters.SshPublicKeyFilters do
  @moduledoc """
  Ecto query filter helpers for the `ssh_public_keys` table.

  Pure query builders. All helpers assume the query is built with
  `ssh_username → node → cluster` joined as bindings `[k, u, n, c]` —
  see `EdgeAdmin.Ssh.list_ssh_public_keys/1`.
  """

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  @doc """
  Applies `node_id` filter via the joined node binding (`n.id`).
  """
  def apply_node_id(query, []), do: query

  def apply_node_id(query, filters) do
    Enum.reduce(filters, query, fn
      %{op: :==, value: value}, acc when is_binary(value) ->
        from([_k, _u, n] in acc, where: n.id == ^value)

      %{op: :in, value: values}, acc when is_list(values) ->
        from([_k, _u, n] in acc, where: n.id in ^values)

      _filter, acc ->
        acc
    end)
  end

  @doc """
  Applies `ssh_username_ids` IN filter via the joined ssh_username binding (`u.id`).
  """
  def apply_ssh_username_ids(query, []), do: query

  def apply_ssh_username_ids(query, filters) do
    Enum.reduce(filters, query, fn
      %{op: :in, value: values}, acc when is_list(values) ->
        from([_k, u] in acc, where: u.id in ^values)

      %{op: :==, value: value}, acc when is_binary(value) ->
        from([_k, u] in acc, where: u.id == ^value)

      _filter, acc ->
        acc
    end)
  end

  @doc """
  Applies `username` filter via the joined ssh_username binding (`u.username`).
  Supports exact match, ilike wildcard, and exact IN (`usernames`).
  """
  def apply_username(query, []), do: query

  def apply_username(query, filters) do
    Enum.reduce(filters, query, fn
      %{op: :==, value: value}, acc when is_binary(value) ->
        from([_k, u] in acc, where: u.username == ^value)

      %{op: :ilike, value: value}, acc when is_binary(value) ->
        from([_k, u] in acc, where: case_insensitive_like(u.username, ^value))

      %{op: :in, value: values}, acc when is_list(values) ->
        from([_k, u] in acc, where: u.username in ^values)

      _filter, acc ->
        acc
    end)
  end

  @doc """
  Applies `cluster_name` filter via the joined cluster binding (`c.name`).
  """
  def apply_cluster_name(query, []), do: query

  def apply_cluster_name(query, filters) do
    Enum.reduce(filters, query, fn
      %{op: :==, value: value}, acc when is_binary(value) ->
        from([_k, _u, _n, c] in acc, where: c.name == ^value)

      %{op: :ilike, value: value}, acc when is_binary(value) ->
        from([_k, _u, _n, c] in acc, where: case_insensitive_like(c.name, ^value))

      %{op: :in, value: values}, acc when is_list(values) ->
        from([_k, _u, _n, c] in acc, where: c.name in ^values)

      _filter, acc ->
        acc
    end)
  end
end
