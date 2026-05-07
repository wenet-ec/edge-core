# edge_admin/lib/edge_admin_web/controllers/changeset_json.ex
defmodule EdgeAdminWeb.Controllers.ChangesetJSON do
  @moduledoc """
  Renders validation error envelopes from Ecto changesets (422).
  Details are the full traversed error map — see `EdgeAdmin.ChangesetErrors`
  for the canonical translator (shared with MCP).
  """

  alias EdgeAdmin.ChangesetErrors
  alias EdgeAdminWeb.ResponseEnvelope

  def error(%{conn: conn, changeset: changeset}) do
    ResponseEnvelope.error(conn, "validation_failed", "Validation failed", ChangesetErrors.traverse(changeset))
  end
end
