# edge_admin/lib/edge_admin_web/controllers/admins/discovery_json.ex
defmodule EdgeAdminWeb.Controllers.Admins.DiscoveryJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, admin_name: admin_name}) do
    ResponseEnvelope.success(conn, %{name: admin_name})
  end
end
