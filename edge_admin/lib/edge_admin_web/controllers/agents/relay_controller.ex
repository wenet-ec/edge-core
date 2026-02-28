# edge_admin_web/controllers/agents/relay_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.RelayController do
  use EdgeAdminWeb, :controller

  alias EdgeAdmin.EdgeClusters

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:create]

  @doc """
  Registers an agent to use this admin as its relay gateway.

  Agent authenticates via API token. Admin assigns the agent to use
  this admin as its relay gateway.

  Returns {"data": {"relay_admin_name": "admin-abc123"}}
  """
  def create(conn, _params) do
    edge_node = conn.assigns.current_node

    with {:ok, admin_name} <- EdgeClusters.assign_agent_to_relay(edge_node) do
      conn
      |> put_status(:created)
      |> render(:create, relay_admin_name: admin_name)
    end
  end
end
