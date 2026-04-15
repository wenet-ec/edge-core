# edge_admin/lib/edge_admin_web/controllers/admins/admin_cluster_json.ex
defmodule EdgeAdminWeb.Controllers.Admins.AdminClusterJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def show(%{conn: conn, admin_cluster: admin_cluster}) do
    ResponseEnvelope.success(conn, admin_cluster)
  end
end
