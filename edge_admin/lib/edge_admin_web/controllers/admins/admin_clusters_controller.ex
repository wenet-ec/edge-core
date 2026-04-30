# edge_admin/lib/edge_admin_web/controllers/admins/admin_clusters_controller.ex
defmodule EdgeAdminWeb.Controllers.Admins.AdminClustersController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdminWeb.Schemas.Admins.AdminSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index]

  tags(["Admins.Metadata"])

  operation(:index,
    summary: "List all admin clusters from Netmaker",
    description: """
    Lists every admin cluster Netmaker knows about, with each cluster's admins.
    Includes admins this instance is not a member of (cross-cluster visibility)
    and may include stale entries.
    """,
    responses: %{
      200 => {"Admin clusters", "application/json", AdminSchemas.AdminClustersResponse},
      503 => {"Netmaker unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def index(conn, _params) do
    with {:ok, admin_clusters} <- EdgeAdmin.Admins.list_admin_clusters() do
      render(conn, :index, conn: conn, admin_clusters: admin_clusters)
    end
  end
end
