# edge_admin/lib/edge_admin_web/controllers/admins/edge_clusters_json.ex
defmodule EdgeAdminWeb.Controllers.Admins.EdgeClustersJSON do
  @doc """
  Renders all edge cluster assignments.
  """
  def index(%{edge_clusters: edge_clusters}) do
    edge_clusters
  end
end
