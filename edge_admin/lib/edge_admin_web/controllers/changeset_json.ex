# edge_admin/lib/edge_admin_web/controllers/changeset_json.ex
defmodule EdgeAdminWeb.Controllers.ChangesetJSON do
  @moduledoc """
  Renders validation error envelopes from Ecto changesets (422).
  Details are the full traversed error map from traverse_errors/2,
  which may be nested for embedded schemas and associations.
  """

  alias EdgeAdminWeb.ResponseEnvelope

  def error(%{conn: conn, changeset: changeset}) do
    details = Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
    ResponseEnvelope.error(conn, "validation_failed", "Validation failed", details)
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
