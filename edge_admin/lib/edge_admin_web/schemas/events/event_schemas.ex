# edge_admin/lib/edge_admin_web/schemas/events/event_schemas.ex
defmodule EdgeAdminWeb.Schemas.Events.EventSchemas do
  @moduledoc """
  OpenAPI schemas for event publish actions.
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule EventTestResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(
        %Schema{
          type: :object,
          properties: %{
            published: %Schema{
              type: :boolean,
              description: "True when Core accepted the test event for normal event delivery.",
              example: true
            },
            event: %Schema{
              type: :object,
              description: "The CloudEvents envelope generated for this test publish.",
              properties: %{
                specversion: %Schema{type: :string, example: "1.0"},
                id: %Schema{type: :string, format: :uuid},
                source: %Schema{type: :string, example: "https://github.com/wenet-ec/edge-core"},
                type: %Schema{type: :string, example: "edge.core.test"},
                time: %Schema{type: :string, format: :"date-time"},
                datacontenttype: %Schema{type: :string, example: "application/json"},
                corename: %Schema{type: :string, example: "prod-us"},
                data: %Schema{
                  type: :object,
                  properties: %{
                    message: %Schema{type: :string, example: "Test event from Edge Core"},
                    requested_at: %Schema{type: :string, format: :"date-time"}
                  },
                  required: [:message, :requested_at]
                }
              },
              required: [:specversion, :id, :source, :type, :time, :datacontenttype, :corename, :data]
            }
          },
          required: [:published, :event],
          example: %{
            published: true,
            event: %{
              specversion: "1.0",
              id: "550e8400-e29b-41d4-a716-446655440000",
              source: "https://github.com/wenet-ec/edge-core",
              type: "edge.core.test",
              time: "2026-04-13T10:00:00Z",
              datacontenttype: "application/json",
              corename: "prod-us",
              data: %{
                message: "Test event from Edge Core",
                requested_at: "2026-04-13T10:00:00Z"
              }
            }
          }
        },
        "EventTestResponse",
        "Core test event accepted for normal event delivery."
      )
    )
  end
end
