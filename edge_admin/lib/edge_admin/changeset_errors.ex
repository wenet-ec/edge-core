# edge_admin/lib/edge_admin/changeset_errors.ex
defmodule EdgeAdmin.ChangesetErrors do
  @moduledoc """
  Canonical rendering of `Ecto.Changeset` errors for public-API surfaces.

  Structured rendering preserves field paths for clients, while flat rendering
  produces a single message for protocols that accept only string errors.
  """

  @doc """
  Runs `Ecto.Changeset.traverse_errors/2` with the canonical interpolator.
  Returns a map shaped like `%{field => [msg, ...]}` or, for embedded
  schemas, `%{field => %{nested_field => [msg, ...]}}`.

  Returns field-level details for structured validation responses.
  """
  @spec traverse(Ecto.Changeset.t()) :: map()
  def traverse(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, &interpolate/1)
  end

  @doc """
  Renders the changeset's errors as a single semicolon-joined string,
  with nested paths joined by `.`. Returns `"Validation failed"` (no
  detail) if no errors are present.

  Returns a single validation message for string-based error responses.
  """
  @spec to_flat_string(Ecto.Changeset.t()) :: String.t()
  def to_flat_string(%Ecto.Changeset{} = changeset) do
    case flatten(traverse(changeset)) do
      [] -> "Validation failed"
      pairs -> "Validation failed: " <> Enum.map_join(pairs, "; ", fn {path, msg} -> "#{path} #{msg}" end)
    end
  end

  defp interpolate({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  # Walks the traversed-errors map producing a flat list of {dotted_path, msg}
  # tuples, one per error message (a field with multiple messages produces
  # multiple tuples).
  defp flatten(errors), do: do_flatten(errors, [], [])

  defp do_flatten(map, prefix, acc) when is_map(map) do
    Enum.reduce(map, acc, fn {key, value}, acc ->
      do_flatten(value, [to_string(key) | prefix], acc)
    end)
  end

  defp do_flatten(messages, prefix, acc) when is_list(messages) do
    path = prefix |> Enum.reverse() |> Enum.join(".")
    Enum.reduce(messages, acc, fn msg, acc -> [{path, msg} | acc] end)
  end
end
