# edge_admin/lib/edge_admin_web/controllers/admins/orphaned_clusters_json.ex
defmodule EdgeAdminWeb.Controllers.Admins.OrphanedClustersJSON do
  @moduledoc """
  JSON rendering for orphaned cluster assignments.
  """

  @doc """
  Renders all clusters with no assigned admin instance.
  """
  def index(%{orphaned_clusters: orphaned_clusters}) do
    %{data: orphaned_clusters}
  end
end
