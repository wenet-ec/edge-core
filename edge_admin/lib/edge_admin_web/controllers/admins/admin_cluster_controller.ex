# edge_admin/lib/edge_admin_web/controllers/admins/admin_cluster_controller.ex
defmodule EdgeAdminWeb.Controllers.Admins.AdminClusterController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdminWeb.Schemas.Admins.AdminSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:show]

  tags(["Admins.Metadata"])

  operation(:show,
    summary: "Get this admin's admin cluster",
    description: "Returns metadata and peer topology for the admin cluster this admin belongs to.",
    responses: %{
      200 => {"Admin cluster topology", "application/json", AdminSchemas.MyAdminClusterResponse}
    }
  )

  def show(conn, _params) do
    admin_cluster = EdgeAdmin.Admins.Metadata.get_admin_cluster()
    render(conn, :show, conn: conn, admin_cluster: admin_cluster)
  end
end
