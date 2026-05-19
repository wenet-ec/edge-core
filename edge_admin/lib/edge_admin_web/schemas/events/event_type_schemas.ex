# edge_admin/lib/edge_admin_web/schemas/events/event_type_schemas.ex
defmodule EdgeAdminWeb.Schemas.Events.EventTypeSchemas do
  @moduledoc """
  OpenAPI schemas for the event-type catalog endpoint.
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule EventTypeListResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(
        %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: """
          Full catalog of event types Edge Core can publish, in catalog order.

          Use this list to build a webhook's `subscribed_events` array — every
          entry here is a valid value, anything else is rejected at create time.
          The list is static (code-owned). See [AsyncAPI spec](/asyncdoc) for
          each event's payload shape.
          """,
          example: [
            "edge.enrollment_key.verified",
            "edge.node.registered",
            "edge.node.reregistered",
            "edge.node.version_changed",
            "edge.node.status_changed",
            "edge.node.update_triggered",
            "edge.command_execution.created",
            "edge.command_execution.sent",
            "edge.command_execution.completed",
            "edge.command_execution.cancelled",
            "edge.command_execution.expired",
            "edge.command_execution.pruned",
            "edge.ssh_username.verified",
            "edge.self_update_request.completed"
          ]
        },
        "EventTypeListResponse",
        "Full catalog of event types Edge Core can publish."
      )
    )
  end
end
