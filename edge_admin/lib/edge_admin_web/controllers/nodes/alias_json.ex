# edge_admin/lib/edge_admin_web/controllers/nodes/alias_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.AliasJSON do
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, aliases: aliases, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(aliases, &Alias.to_public/1), flop_meta)
  end

  def show(%{conn: conn, alias: alias_record}) do
    ResponseEnvelope.success(conn, Alias.to_public(alias_record))
  end
end
