# edge_admin/lib/edge_admin_web/controllers/agents/setting_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.SettingController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.IngressTunneling
  alias EdgeAdminWeb.Schemas.Agents.SettingSchema
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  # A reachable degraded admin must still provide routing configuration so an
  # agent can learn replacement Admin and canonical Core-map hostnames.
  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:config]

  tags(["Internal.Agents"])

  operation(:config,
    summary: "Pull agent settings config",
    description: "Returns non-secret settings config, including this Agent Node's Ingress Tunneling configuration.",
    responses: %{
      200 => {"Settings config", "application/json", SettingSchema.ConfigResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def config(conn, _params) do
    with {:ok, ingress_tunneling} <- IngressTunneling.get_ingress_tunneling(conn.assigns.current_node.id) do
      render(conn, :config,
        conn: conn,
        admin_urls: Application.fetch_env!(:edge_admin, :admin_urls),
        core_derp_map_urls: Application.get_env(:edge_admin, :core_derp_map_urls, []),
        ingress_tunneling: ingress_tunneling
      )
    end
  end
end
