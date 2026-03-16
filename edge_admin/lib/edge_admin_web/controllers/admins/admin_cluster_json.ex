# edge_admin/lib/edge_admin_web/controllers/admins/admin_cluster_json.ex
defmodule EdgeAdminWeb.Controllers.Admins.AdminClusterJSON do
  @moduledoc """
  JSON rendering for admin cluster topology.
  """

  @doc """
  Renders admin cluster topology.
  """
  def show(%{admin_cluster: admin_cluster}) do
    %{data: admin_cluster}
  end
end
