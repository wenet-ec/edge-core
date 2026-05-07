# edge_admin/lib/edge_admin/changeset_errors.ex
defmodule EdgeAdmin.ChangesetErrors do
  @moduledoc """
  Canonical rendering of `Ecto.Changeset` errors for public-API surfaces.

  Both REST (`EdgeAdminWeb.Controllers.ChangesetJSON`) and MCP
  (`EdgeAdminMcp.ToolError`) read from this module so the *interpolated
  message text* is identical across surfaces. Each surface still renders
  the result the way its protocol requires:

  - REST: returns the structured map (`traverse/1`) inside the JSON
    envelope so clients can key off field names programmatically.
  - MCP: flattens to a single string (`to_flat_string/1`) because tool
    errors are bare strings on the wire and the model consumes them as
    natural language.

  ## Why share

  Without this module, the two surfaces independently translated the
  same `{"can't be %{kind}", kind: "blank"}` opt tuples. They produced
  the same text by accident, not by contract — drift between them was
  one careless edit away.
  """

  @doc """
  Runs `Ecto.Changeset.traverse_errors/2` with the canonical interpolator.
  Returns a map shaped like `%{field => [msg, ...]}` or, for embedded
  schemas, `%{field => %{nested_field => [msg, ...]}}`.

  Used by REST to render the `details` payload in the validation-error
  envelope.
  """
  @spec traverse(Ecto.Changeset.t()) :: map()
  def traverse(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, &interpolate/1)
  end

  @doc """
  Renders the changeset's errors as a single semicolon-joined string,
  with nested paths joined by `.`. Returns `"Validation failed"` (no
  detail) if no errors are present.

  Examples:

      "name can't be blank; targeting.type is invalid"

  Used by MCP to render tool errors that fit the protocol's
  one-string-per-error contract.
  """
  @spec to_flat_string(Ecto.Changeset.t()) :: String.t()
  def to_flat_string(%Ecto.Changeset{} = changeset) do
    case flatten(traverse(changeset)) do
      [] -> "Validation failed"
      pairs -> "Validation failed: " <> Enum.map_join(pairs, "; ", fn {path, msg} -> "#{path} #{msg}" end)
    end
  end

  # ── Internals ─────────────────────────────────────────────────────────────

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
