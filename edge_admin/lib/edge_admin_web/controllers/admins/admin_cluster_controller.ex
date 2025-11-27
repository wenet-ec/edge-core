# edge_admin/lib/edge_admin_web/controllers/admins/admin_cluster_controller.ex
defmodule EdgeAdminWeb.Controllers.Admins.AdminClusterController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdminWeb.Schemas.Admins.AdminSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  tags(["Admins.Metadata"])

  operation(:show,
    summary: "Get admin cluster topology",
    description: "Returns admin cluster metadata and peer topology from ETS",
    responses: %{
      200 => {"Admin cluster topology", "application/json", AdminSchemas.AdminClusterResponse}
    }
  )

  def show(conn, _params) do
    [{:admin_cluster, admin_cluster}] = :ets.lookup(:metadata, :admin_cluster)

    conn
    |> put_status(:ok)
    |> json(admin_cluster)
  end
end
