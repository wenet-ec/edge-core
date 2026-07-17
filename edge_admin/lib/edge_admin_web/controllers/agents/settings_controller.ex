# edge_admin/lib/edge_admin_web/controllers/agents/settings_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.SettingsController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdminWeb.Schemas.Agents.SettingsSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  # A reachable degraded admin must still provide routing configuration so an
  # agent can learn replacement Admin and canonical Core-map hostnames.
  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:config]

  tags(["Internal.Agents"])

  operation(:config,
    summary: "Get refreshable settings config",
    description: "Returns non-secret settings config for the authenticated agent.",
    responses: %{
      200 => {"Settings config", "application/json", SettingsSchemas.ConfigResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def config(conn, _params) do
    render(conn, :config,
      conn: conn,
      admin_urls: Application.fetch_env!(:edge_admin, :admin_urls),
      core_derp_map_urls: Application.get_env(:edge_admin, :core_derp_map_urls, [])
    )
  end
end
