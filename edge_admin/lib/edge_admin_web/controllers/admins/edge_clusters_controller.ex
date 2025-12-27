# edge_admin/lib/edge_admin_web/controllers/admins/edge_clusters_controller.ex
defmodule EdgeAdminWeb.Controllers.Admins.EdgeClustersController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdminWeb.Schemas.Admins.AdminSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index]

  tags(["Admins.Metadata"])

  operation(:index,
    summary: "Get all edge cluster assignments",
    description: "Returns all edge cluster assignments across all admins from metadata",
    responses: %{
      200 => {"Edge clusters", "application/json", AdminSchemas.EdgeClustersResponse}
    }
  )

  def index(conn, _params) do
    edge_clusters = EdgeAdmin.Admins.Metadata.get_edge_clusters()
    render(conn, :index, edge_clusters: edge_clusters)
  end
end
