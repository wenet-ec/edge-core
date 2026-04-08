# edge_admin/lib/edge_admin_web/schemas/agents/alias_schemas.ex
defmodule EdgeAdminWeb.Schemas.Agents.AliasSchemas do
  @moduledoc """
  OpenAPI schemas for agent alias registration endpoints.
  """

  use EdgeAdminWeb.Schema

  alias OpenApiSpex.Schema

  defmodule CreateAliasRequest do
    @moduledoc false

    schema(%{
      title: "Internal.CreateAliasRequest",
      description: "Alias name to register for this node",
      type: :object,
      properties: %{
        name: %Schema{
          type: :string,
          description: "Alias name (lowercase alphanumeric with hyphens)",
          example: "web-server"
        }
      },
      required: [:name],
      example: %{name: "web-server"}
    })
  end

  defmodule AliasSingleResponse do
    @moduledoc false

    schema(%{
      title: "Internal.AliasSingleResponse",
      description: "Alias created successfully",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string, format: :uuid, description: "Alias UUID"},
            name: %Schema{type: :string, description: "Alias name"},
            node_id: %Schema{type: :string, format: :uuid, description: "Node UUID"}
          },
          required: [:id, :name, :node_id]
        }
      },
      required: [:data],
      example: %{
        data: %{
          id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
          name: "web-server",
          node_id: "01234567-89ab-cdef-0123-456789abcdef"
        }
      }
    })
  end
end
