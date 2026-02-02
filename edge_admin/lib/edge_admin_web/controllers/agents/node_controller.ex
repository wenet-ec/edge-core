# edge_admin/lib/edge_admin_web/controllers/agents/node_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.NodeController do
  use EdgeAdminWeb, :controller

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Plugs.DegradedMode

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug DegradedMode, :block when action in [:create]
  plug DegradedMode, :allow when action in [:update_health_check]

  @doc """
  Node registration endpoint (no authentication required).

  Agent registers itself with admin, receives api_token and proxy_password.
  """
  def create(conn, params) do
    with {:ok, node} <- Nodes.register_node(params) do
      conn
      |> put_status(:created)
      |> render(:show, node: node)
    end
  end

  @doc """
  Node health check report endpoint (requires authentication).

  Agent reports its health status when using HTTP fallback mode.
  Node ID is inferred from conn.assigns.current_node (authenticated via API token).
  """
  def update_health_check(conn, params) do
    # Get node from authenticated context (set by AgentAuth plug)
    node = conn.assigns.current_node

    with {:ok, updated_node} <- Nodes.update_node_health_check(node, params) do
      render(conn, :show, node: updated_node)
    end
  end
end
