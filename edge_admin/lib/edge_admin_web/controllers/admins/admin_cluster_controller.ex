# edge_admin/lib/edge_admin_web/controllers/admins/admin_cluster_controller.ex
defmodule EdgeAdminWeb.Controllers.Admins.AdminClusterController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdminWeb.Schemas.Admins.AdminSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:show]

  tags(["Admins.Metadata"])

  operation(:show,
    summary: "Get admin cluster topology",
    description: "Returns admin cluster metadata and peer topology",
    responses: %{
      200 => {"Admin cluster topology", "application/json", AdminSchemas.AdminClusterResponse}
    }
  )

  def show(conn, _params) do
    admin_cluster = EdgeAdmin.Admins.Metadata.get_admin_cluster()
    render(conn, :show, admin_cluster: admin_cluster)
  end
end
