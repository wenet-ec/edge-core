# edge_admin/lib/edge_admin_web/controllers/admins/discovery_controller.ex
defmodule EdgeAdminWeb.Controllers.Admins.DiscoveryController do
  use EdgeAdminWeb, :controller

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index]

  def index(conn, _params) do
    admin_name = Application.get_env(:edge_admin, :admin_name)
    render(conn, :index, admin_name: admin_name)
  end
end
