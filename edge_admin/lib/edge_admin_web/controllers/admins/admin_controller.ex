# edge_admin/lib/edge_admin_web/controllers/admins/admin_controller.ex
defmodule EdgeAdminWeb.Controllers.Admins.AdminController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdminWeb.Schemas.Admins.AdminSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  tags(["Admins.Metadata"])

  operation(:show,
    summary: "Get this admin's identity",
    description: "Returns this admin's identity and configuration from metadata",
    responses: %{
      200 => {"Admin identity", "application/json", AdminSchemas.AdminResponse}
    }
  )

  def show(conn, _params) do
    admin = EdgeAdmin.Admins.Metadata.get_admin()

    conn
    |> put_status(:ok)
    |> json(admin)
  end
end
