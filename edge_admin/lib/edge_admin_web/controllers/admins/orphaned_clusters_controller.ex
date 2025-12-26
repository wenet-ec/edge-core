# edge_admin/lib/edge_admin_web/controllers/admins/orphaned_clusters_controller.ex
defmodule EdgeAdminWeb.Controllers.Admins.OrphanedClustersController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdminWeb.Schemas.Admins.AdminSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  tags(["Admins.Metadata"])

  operation(:index,
    summary: "Get all orphaned clusters",
    description:
      "Returns all clusters that could not be assigned to any admin due to capacity constraints. Empty map when system is not degraded.",
    responses: %{
      200 => {"Orphaned clusters", "application/json", AdminSchemas.OrphanedClustersResponse}
    }
  )

  def index(conn, _params) do
    orphaned_clusters = EdgeAdmin.Admins.Metadata.get_orphaned_clusters()

    conn
    |> put_status(:ok)
    |> json(orphaned_clusters)
  end
end
