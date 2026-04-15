# edge_admin/lib/edge_admin_web/schemas/agents/alias_schemas.ex
defmodule EdgeAdminWeb.Schemas.Agents.AliasSchemas do
  @moduledoc """
  OpenAPI schemas for agent alias registration endpoints.
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
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

  defmodule AliasData do
    @moduledoc false

    schema(%{
      title: "Internal.AliasData",
      description: "Alias created successfully",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, description: "Alias UUID"},
        name: %Schema{type: :string, description: "Alias name"},
        node_id: %Schema{type: :string, format: :uuid, description: "Node UUID"}
      },
      required: [:id, :name, :node_id],
      example: %{
        id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        name: "web-server",
        node_id: "01234567-89ab-cdef-0123-456789abcdef"
      }
    })
  end

  defmodule AliasSingleResponse do
    @moduledoc false

    schema(CommonSchemas.single_response(AliasData, "Internal.AliasSingleResponse", "Alias created successfully"))
  end
end
