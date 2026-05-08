# edge_admin/lib/edge_admin_web/controllers/events/event_type_controller.ex
defmodule EdgeAdminWeb.Controllers.Events.EventTypeController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Events.Catalog
  alias EdgeAdminWeb.Schemas.Events.EventTypeSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index]

  tags(["Events.Type"])

  operation(:index,
    summary: "List event types",
    description:
      "Returns the full catalog of event types Edge Core can publish. Use this list to build a webhook's `subscribed_events` array — every value here is valid, anything else is rejected at create time. Static, code-owned list. See [AsyncAPI spec](/asyncdoc) for each event's payload shape.",
    responses: %{
      200 => {"Event types", "application/json", EventTypeSchemas.EventTypeListResponse}
    }
  )

  def index(conn, _params) do
    render(conn, :index, conn: conn, event_types: Catalog.all_event_types())
  end
end
