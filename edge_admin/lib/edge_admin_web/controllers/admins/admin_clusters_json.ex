# edge_admin/lib/edge_admin_web/controllers/admins/admin_clusters_json.ex
defmodule EdgeAdminWeb.Controllers.Admins.AdminClustersJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, admin_clusters: admin_clusters}) do
    ResponseEnvelope.success(conn, admin_clusters)
  end
end
