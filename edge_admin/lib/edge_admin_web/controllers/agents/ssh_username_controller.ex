# edge_admin/lib/edge_admin_web/controllers/agents/ssh_username_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.SshUsernameController do
  use EdgeAdminWeb, :controller

  alias EdgeAdmin.Nodes

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  @doc """
  SSH credentials query endpoint (requires authentication).

  Agent's SSH server fetches allowed credentials during auth.
  Node ID is inferred from conn.assigns.current_node.
  """
  def index(conn, _params) do
    # Get node ID from authenticated context (set by AgentAuth plug)
    node_id = conn.assigns.current_node.id

    # Query SSH usernames with preloaded public keys
    ssh_usernames = Nodes.list_ssh_usernames_for_node(node_id)

    render(conn, :index, ssh_usernames: ssh_usernames)
  end
end
