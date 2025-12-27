# edge_admin/lib/edge_admin_web/controllers/admins/discovery_json.ex
defmodule EdgeAdminWeb.Controllers.Admins.DiscoveryJSON do
  @doc """
  Renders admin discovery information.
  """
  def index(%{admin_name: admin_name}) do
    %{name: admin_name}
  end
end
