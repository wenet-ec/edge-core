# edge_admin/lib/edge_admin_web/controllers/admins/admin_controller.ex
defmodule EdgeAdminWeb.Controllers.Admins.AdminController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdminWeb.Schemas.Admins.AdminSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EdgeAdminWeb.Plugs.CastAndValidateErrorRenderer
  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:show]

  tags(["Admins.Metadata"])

  operation(:show,
    summary: "Get the current admin",
    description: "Returns the current admin's identity and configuration from metadata.",
    responses: %{
      200 => {"Admin identity", "application/json", AdminSchemas.AdminResponse}
    }
  )

  def show(conn, _params) do
    admin = EdgeAdmin.Admins.Metadata.get_admin()
    render(conn, :show, conn: conn, admin: admin)
  end
end
