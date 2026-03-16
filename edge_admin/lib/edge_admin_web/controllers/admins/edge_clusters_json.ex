# edge_admin/lib/edge_admin_web/controllers/admins/edge_clusters_json.ex
defmodule EdgeAdminWeb.Controllers.Admins.EdgeClustersJSON do
  @moduledoc """
  JSON rendering for edge cluster assignments.
  """

  @doc """
  Renders all edge cluster assignments across all admins.
  """
  def index(%{edge_clusters: edge_clusters}) do
    %{data: edge_clusters}
  end
end
