# edge_admin/lib/edge_admin_web/controllers/events/event_type_json.ex
defmodule EdgeAdminWeb.Controllers.Events.EventTypeJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, event_types: event_types}) do
    ResponseEnvelope.success(conn, event_types)
  end
end
