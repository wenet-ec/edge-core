# edge_admin/lib/edge_admin_web/controllers/events/event_controller.ex
defmodule EdgeAdminWeb.Controllers.Events.EventController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Events
  alias EdgeAdminWeb.Schemas.Events.EventSchemas

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:test]

  tags(["Events.Event"])

  operation(:test,
    summary: "Publish test event",
    description:
      "Publishes the official `edge.core.test` event through the normal event delivery path. " <>
        "The event is enqueued for the configured broker, if enabled, and delivered to webhooks " <>
        "whose `subscribed_events` includes `edge.core.test`.",
    responses: %{
      202 => {"Test event accepted", "application/json", EventSchemas.EventTestResponse}
    }
  )

  def test(conn, _params) do
    {:ok, envelope} = Events.publish_test()

    conn
    |> put_status(:accepted)
    |> render(:test, conn: conn, envelope: envelope)
  end
end
