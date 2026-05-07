# edge_admin/lib/edge_admin_web/controllers/nodes/node_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.NodeJSON do
  alias EdgeAdmin.Nodes.Views.NodeView
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, nodes: nodes, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(nodes, &NodeView.render/1), flop_meta)
  end

  def show(%{conn: conn, node: node}) do
    ResponseEnvelope.success(conn, NodeView.render(node))
  end
end
