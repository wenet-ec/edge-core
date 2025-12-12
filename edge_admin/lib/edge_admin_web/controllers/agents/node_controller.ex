# edge_admin/lib/edge_admin_web/controllers/agents/node_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.NodeController do
  use EdgeAdminWeb, :controller

  alias EdgeAdmin.Nodes

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  @doc """
  Node registration endpoint (no authentication required).

  Agent registers itself with admin, receives api_token and proxy_password.
  """
  def create(conn, params) do
    with {:ok, node} <- Nodes.register_agent_node(params) do
      conn
      |> put_status(:created)
      |> render(:show, node: node)
    end
  end
end
