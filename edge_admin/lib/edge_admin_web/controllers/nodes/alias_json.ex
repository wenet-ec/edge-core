# edge_admin/lib/edge_admin_web/controllers/nodes/alias_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.AliasJSON do
  alias EdgeAdmin.Nodes.Views.AliasView
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, aliases: aliases, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(aliases, &AliasView.render/1), flop_meta)
  end

  def show(%{conn: conn, alias: alias_record}) do
    ResponseEnvelope.success(conn, AliasView.render(alias_record))
  end
end
