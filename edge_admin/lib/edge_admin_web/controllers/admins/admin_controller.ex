# edge_admin/lib/edge_admin_web/controllers/admins/admin_controller.ex
defmodule EdgeAdminWeb.Controllers.Admins.AdminController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdminWeb.Schemas.Admins.AdminSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  tags(["Admins.Metadata"])

  operation(:show,
    summary: "Get this admin's identity",
    description: "Returns this admin's identity and configuration from ETS metadata",
    responses: %{
      200 => {"Admin identity", "application/json", AdminSchemas.AdminResponse}
    }
  )

  def show(conn, _params) do
    [{:admin, admin}] = :ets.lookup(:metadata, :admin)

    conn
    |> put_status(:ok)
    |> json(%{
      id: admin.id,
      name: admin.name,
      max_capacity: admin.max_capacity,
      erlang_node_name: to_string(admin.erlang_node_name),
      dns_hostname: admin.dns_hostname,
      admin_cluster_name: admin.admin_cluster_name,
      last_computed_at: admin.last_computed_at
    })
  end
end
