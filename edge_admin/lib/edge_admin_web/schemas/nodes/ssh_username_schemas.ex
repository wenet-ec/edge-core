# edge_admin/lib/edge_admin_web/schemas/nodes/ssh_username_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.SshUsernameSchemas do
  @moduledoc """
  OpenAPI schemas for SSH Username resources
  """

  alias OpenApiSpex.Schema
  alias EdgeAdminWeb.Schemas.CommonSchemas

  defmodule SshUsernameResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SSH Username",
      description: "SSH username information for node access",
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          format: :uuid,
          description: "Unique SSH username identifier"
        },
        username: %Schema{
          type: :string,
          description: "SSH username for node access",
          example: "admin"
        },
        node_id: %Schema{
          type: :string,
          format: :uuid,
          description: "Node this username belongs to"
        },
        inserted_at: %Schema{
          type: :string,
          format: :datetime,
          description: "When the SSH username was created"
        },
        updated_at: %Schema{
          type: :string,
          format: :datetime,
          description: "When the SSH username was last updated"
        }
      },
      required: [:id, :username, :node_id, :inserted_at, :updated_at],
      example: %{
        id: "01234567-89ab-cdef-0123-456789abcdef",
        username: "admin",
        node_id: "fedcba98-7654-3210-fedc-ba9876543210",
        inserted_at: "2025-06-23T10:30:00Z",
        updated_at: "2025-06-23T10:30:00Z"
      }
    })
  end

  defmodule SshUsernamePaginatedResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(
      CommonSchemas.paginated_response(
        SshUsernameResponse,
        "SSH Username Paginated Response",
        "Paginated list of SSH usernames with filtering and sorting metadata"
      )
    )
  end

  defmodule SshUsernameSingleResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SSH Username Single Response",
      description: "Single SSH username response",
      type: :object,
      properties: %{
        data: SshUsernameResponse
      },
      required: [:data],
      example: %{
        data: %{
          id: "01234567-89ab-cdef-0123-456789abcdef",
          username: "admin",
          node_id: "fedcba98-7654-3210-fedc-ba9876543210",
          inserted_at: "2025-06-23T10:30:00Z",
          updated_at: "2025-06-23T10:30:00Z"
        }
      }
    })
  end

  defmodule SshUsernameCreateRequest do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SSH Username Create Request",
      description: "Create a new SSH username for a node",
      type: :object,
      properties: %{
        ssh_username: %Schema{
          type: :object,
          properties: %{
            username: %Schema{
              type: :string,
              description: "SSH username for node access",
              example: "admin"
            }
          },
          required: [:username],
          example: %{
            username: "admin"
          }
        }
      },
      required: [:ssh_username]
    })
  end
end
