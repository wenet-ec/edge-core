# edge_admin/lib/edge_admin_web/controllers/admins/discovery_json.ex
defmodule EdgeAdminWeb.Controllers.Admins.DiscoveryJSON do
  @moduledoc """
  JSON rendering for admin discovery.
  """

  @doc """
  Renders admin discovery information for agent bootstrap.
  """
  def index(%{admin_name: admin_name}) do
    %{data: %{name: admin_name}}
  end
end
