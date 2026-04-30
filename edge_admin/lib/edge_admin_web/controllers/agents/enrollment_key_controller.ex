# edge_admin_web/controllers/agents/enrollment_key_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.EnrollmentKeyController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdminWeb.Schemas.Agents.EnrollmentKeySchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  tags(["Internal.Agents"])

  operation(:verify,
    summary: "Verify an enrollment key",
    description: "Agent calls this before joining the VPN. Always returns 200 — check `verified` and `error` fields.",
    request_body:
      {"Enrollment key to verify", "application/json", EnrollmentKeySchemas.EnrollmentKeyVerifyRequest, required: true},
    responses: %{
      200 => {"Verification result", "application/json", EnrollmentKeySchemas.EnrollmentKeyVerifyResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse}
    }
  )

  def verify(conn, params) do
    with {:ok, result} <- Nodes.verify_enrollment_key(Map.merge(params, conn.body_params)) do
      render(conn, :verify, conn: conn, result: result)
    end
  end
end
