# edge_admin/lib/edge_admin_web/controllers/agents/ssh_username_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.SshUsernameController do
  @moduledoc """
  Controller for agent SSH credential verification.

  This controller handles requests from edge agents to verify SSH credentials.
  It uses the agent's API token to identify the node.
  """
  use EdgeAdminWeb, :controller

  alias EdgeAdmin.Ssh

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  @doc """
  SSH credentials verification endpoint (requires authentication).

  Agent's SSH server calls this to verify authentication attempts.
  Supports both password and public key authentication.
  Node ID is inferred from conn.assigns.current_node.

  Returns {"data": {"verified": true/false}}
  - true: credential matches
  - false: username not found or credential incorrect (security: don't distinguish)
  """
  def verify_credentials(conn, params) do
    node_id = conn.assigns.current_node.id

    with {:ok, verified} <- Ssh.verify_ssh_credentials(node_id, params) do
      render(conn, :verify_credentials, verified: verified)
    end
  end
end
