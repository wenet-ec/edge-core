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
    case Nodes.register_agent_node(params) do
      {:ok, node, api_token, proxy_password} ->
        conn
        |> put_status(:created)
        |> render(:create, node: node, api_token: api_token, proxy_password: proxy_password)

      {:error, :node_not_found_in_netmaker} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Node not found in Netmaker network"})

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
