# edge_admin/lib/edge_admin_web/controllers/admins/orphaned_clusters_json.ex
defmodule EdgeAdminWeb.Controllers.Admins.OrphanedClustersJSON do
  @doc """
  Renders all orphaned clusters.
  """
  def index(%{orphaned_clusters: orphaned_clusters}) do
    orphaned_clusters
  end
end
