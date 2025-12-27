# edge_admin/lib/edge_admin_web/controllers/admins/admin_cluster_json.ex
defmodule EdgeAdminWeb.Controllers.Admins.AdminClusterJSON do
  @doc """
  Renders admin cluster topology.
  """
  def show(%{admin_cluster: admin_cluster}) do
    admin_cluster
  end
end
