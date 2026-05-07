# edge_admin/lib/edge_admin_web/controllers/nodes/node_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.NodeJSON do
  alias EdgeAdmin.Nodes.Schemas.Node, as: NodeSchema
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, nodes: nodes, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(nodes, &NodeSchema.to_public/1), flop_meta)
  end

  def show(%{conn: conn, node: node}) do
    ResponseEnvelope.success(conn, NodeSchema.to_public(node))
  end
end
