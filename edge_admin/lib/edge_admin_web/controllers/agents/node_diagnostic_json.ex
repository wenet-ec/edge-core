# edge_admin/lib/edge_admin_web/controllers/agents/node_diagnostic_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.NodeDiagnosticJSON do
  alias EdgeAdmin.Nodes.Views.NodeDiagnosticView
  alias EdgeAdminWeb.ResponseEnvelope

  def show(%{conn: conn, diagnostic: diagnostic}) do
    ResponseEnvelope.success(conn, NodeDiagnosticView.render_push(diagnostic))
  end
end
