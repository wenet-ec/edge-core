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

    # Convert topology erlang node names to strings
    topology =
      Enum.map(admin_cluster.topology, fn entry ->
        %{
          id: entry.id,
          max_capacity: entry.max_capacity,
          erlang_node_name: to_string(entry.erlang_node_name)
        }
      end)

    conn
    |> put_status(:ok)
    |> json(%{
      name: admin_cluster.name,
      total_admins: admin_cluster.total_admins,
      degraded: admin_cluster.degraded,
      topology: topology
    })
  end
end
