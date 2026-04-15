# edge_admin/lib/edge_admin_web/controllers/admins/discovery_controller.ex
defmodule EdgeAdminWeb.Controllers.Admins.DiscoveryController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdminWeb.Schemas.Admins.AdminSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EdgeAdminWeb.Plugs.CastAndValidateErrorRenderer
  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index]

  tags(["Internal.Metadata"])

  operation(:index,
    summary: "Admin self-discovery",
    description: "Agent calls this to discover the admin's identity during VPN bootstrap.",
    responses: %{
      200 => {"Admin discovery info", "application/json", AdminSchemas.DiscoveryResponse}
    }
  )

  def index(conn, _params) do
    admin_name = Application.get_env(:edge_admin, :admin_name)
    render(conn, :index, conn: conn, admin_name: admin_name)
  end
end
