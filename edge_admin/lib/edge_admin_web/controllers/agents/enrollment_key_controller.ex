# edge_admin_web/controllers/agents/enrollment_key_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.EnrollmentKeyController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Schemas.Agents.EnrollmentKeySchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  tags(["Internal.Agents"])

  operation(:verify,
    summary: "Verify an enrollment key",
    description: "Agent calls this before joining the VPN. Always returns 200 — check `verified` and `error` fields.",
    responses: %{
      200 => {"Verification result", "application/json", EnrollmentKeySchemas.EnrollmentKeyVerifyResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse}
    }
  )

  def verify(conn, params) do
    with {:ok, result} <- Nodes.verify_enrollment_key(Map.merge(params, conn.body_params)) do
      render(conn, :verify, result: result)
    end
  end
end
