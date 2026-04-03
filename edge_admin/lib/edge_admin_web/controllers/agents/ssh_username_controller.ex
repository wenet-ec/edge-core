# edge_admin/lib/edge_admin_web/controllers/agents/ssh_username_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.SshUsernameController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Ssh
  alias EdgeAdminWeb.Schemas.Agents.SshUsernameSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true
  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:verify_credentials]

  tags(["Internal.Agents"])

  operation(:verify_credentials,
    summary: "Verify SSH credentials",
    description: """
    Agent's SSH server calls this to verify authentication attempts.
    Supports both password and public key authentication.
    Node ID is inferred from the API token.

    Always returns 200 — check `verified` field. Returns false for both
    unknown username and wrong credential (security: don't distinguish).
    """,
    responses: %{
      200 => {"Verification result", "application/json", SshUsernameSchemas.SshCredentialsVerifyResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse}
    }
  )

  def verify_credentials(conn, params) do
    node_id = conn.assigns.current_node.id

    with {:ok, verified} <- Ssh.verify_ssh_credentials(node_id, Map.merge(params, conn.body_params)) do
      render(conn, :verify_credentials, verified: verified)
    end
  end
end
