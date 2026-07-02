# edge_admin/lib/edge_admin_web/controllers/events/event_json.ex
defmodule EdgeAdminWeb.Controllers.Events.EventJSON do
  alias EdgeAdmin.Events.Views.EventView
  alias EdgeAdminWeb.ResponseEnvelope

  def test(%{conn: conn, envelope: envelope}) do
    ResponseEnvelope.success(conn, EventView.render_test(envelope))
  end
end
