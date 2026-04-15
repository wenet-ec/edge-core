# edge_admin_web/controllers/agents/self_update_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.SelfUpdateController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.SelfUpdates
  alias EdgeAdminWeb.Schemas.Agents.SelfUpdateSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EdgeAdminWeb.Plugs.CastAndValidateErrorRenderer
  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:check]

  tags(["Internal.Agents"])

  operation(:check,
    summary: "Check for pending self-update",
    description: "Agent polls for pending self-updates when VPN connectivity is unavailable.",
    responses: %{
      200 => {"Self-update check result", "application/json", SelfUpdateSchemas.SelfUpdateCheckResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def check(conn, _params) do
    node = conn.assigns.current_node

    with {:ok, result} <- SelfUpdates.check_for_latest_request(node) do
      render(conn, :check, conn: conn, result: result)
    end
  end
end
