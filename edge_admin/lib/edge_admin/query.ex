# edge_admin/lib/edge_admin/query.ex
defmodule EdgeAdmin.Query do
  @moduledoc """
  Cross-adapter Ecto query helpers.

  Postgres has `ILIKE` natively; SQLite does not (`ecto_sqlite3` raises
  `"ilike is not supported by SQLite3"`). Anywhere we want a
  case-insensitive `LIKE`, use `case_insensitive_like/2` instead — it
  expands to `fragment("lower(?) LIKE lower(?)", left, right)`, which
  both adapters accept.

  Caveat: `lower/1` is ASCII-only by default in both Postgres and
  SQLite. For ASCII-only data (hostnames, slugs, cluster names) the
  semantics match `ILIKE` exactly; for arbitrary Unicode they may
  differ. Edge Admin's filterable string fields are ASCII-only in
  practice, so this is safe.

  Wildcards (`%`, `_`) in the right-hand value carry the usual SQL
  `LIKE` semantics and are not escaped here — callers control them.
  """

  @doc """
  Case-insensitive LIKE that works on both Postgres and SQLite.

  Use inside an Ecto query in place of `ilike/2`:

      from u in User, where: case_insensitive_like(u.name, ^pattern)
  """
  defmacro case_insensitive_like(left, right) do
    quote do
      fragment("lower(?) LIKE lower(?)", unquote(left), unquote(right))
    end
  end
end
