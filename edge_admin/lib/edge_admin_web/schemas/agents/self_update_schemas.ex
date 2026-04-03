# edge_admin/lib/edge_admin_web/schemas/agents/self_update_schemas.ex
defmodule EdgeAdminWeb.Schemas.Agents.SelfUpdateSchemas do
  @moduledoc """
  OpenAPI schemas for agent self-update check endpoints.
  """

  use EdgeAdminWeb.Schema

  alias OpenApiSpex.Schema

  defmodule SelfUpdateCheckResponse do
    @moduledoc false

    schema(%{
      title: "Internal.SelfUpdateCheckResponse",
      description: "Result of checking whether the latest self-update request targets this node",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            including_me: %Schema{
              type: :boolean,
              description: "Whether the latest self-update request targets this node"
            },
            inserted_at: %Schema{
              type: :string,
              format: :"date-time",
              nullable: true,
              description: "When the self-update request was created, null if no request exists"
            }
          },
          required: [:including_me, :inserted_at]
        }
      },
      required: [:data],
      example: %{
        data: %{
          including_me: true,
          inserted_at: "2026-04-02T10:00:00Z"
        }
      }
    })
  end
end
