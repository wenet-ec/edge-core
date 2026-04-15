# edge_admin/lib/edge_admin_web/controllers/admins/edge_clusters_json.ex
defmodule EdgeAdminWeb.Controllers.Admins.EdgeClustersJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, edge_clusters: edge_clusters}) do
    ResponseEnvelope.success(conn, edge_clusters)
  end
end
