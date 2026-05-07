# edge_admin/lib/edge_admin_web/controllers/nodes/enrollment_key_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.EnrollmentKeyJSON do
  alias EdgeAdmin.Nodes.Views.EnrollmentKeyView
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, enrollment_keys: keys, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(keys, &EnrollmentKeyView.render/1), flop_meta)
  end

  def show(%{conn: conn, enrollment_key: key}) do
    ResponseEnvelope.success(conn, EnrollmentKeyView.render(key))
  end
end
