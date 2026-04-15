# edge_admin/lib/edge_admin_web/controllers/admins/orphaned_clusters_json.ex
defmodule EdgeAdminWeb.Controllers.Admins.OrphanedClustersJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, orphaned_clusters: orphaned_clusters}) do
    ResponseEnvelope.success(conn, orphaned_clusters)
  end
end
