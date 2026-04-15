# edge_admin/lib/edge_admin_web/schemas/agents/self_update_schemas.ex
defmodule EdgeAdminWeb.Schemas.Agents.SelfUpdateSchemas do
  @moduledoc """
  OpenAPI schemas for agent self-update check endpoints.
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule SelfUpdateCheckData do
    @moduledoc false

    schema(%{
      title: "Internal.SelfUpdateCheckData",
      description: "Whether the latest self-update request targets this node",
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
      required: [:including_me, :inserted_at],
      example: %{including_me: true, inserted_at: "2026-04-02T10:00:00Z"}
    })
  end

  defmodule SelfUpdateCheckResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(
        SelfUpdateCheckData,
        "Internal.SelfUpdateCheckResponse",
        "Result of checking whether the latest self-update request targets this node"
      )
    )
  end
end
