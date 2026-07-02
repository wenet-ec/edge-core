# edge_admin/lib/edge_admin_web/controllers/events/event_json.ex
defmodule EdgeAdminWeb.Controllers.Events.EventJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def test(%{conn: conn, envelope: envelope}) do
    ResponseEnvelope.success(conn, %{
      published: true,
      event: envelope
    })
  end
end
