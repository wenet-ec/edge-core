# edge_admin/lib/edge_admin_web/controllers/admins/admin_json.ex
defmodule EdgeAdminWeb.Controllers.Admins.AdminJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def show(%{conn: conn, admin: admin}) do
    ResponseEnvelope.success(conn, admin)
  end
end
