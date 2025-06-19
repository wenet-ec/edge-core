# edge_admin/lib/edge_admin_web/schemas/commands/command_schemas.ex
defmodule EdgeAdminWeb.Schemas.Commands.CommandSchemas do
  @moduledoc """
  OpenAPI schemas for Command resources
  """

  alias OpenApiSpex.Schema
  alias EdgeAdminWeb.Schemas.CommonSchemas

  defmodule CommandResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Command",
      description: "Command information",
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          format: :uuid,
          description: "Unique command identifier"
        },
        command_text: %Schema{
          type: :string,
          description: "Multi-line shell script/commands",
          example: "ABC=value\necho $ABC\nsystemctl restart nginx"
        },
        inserted_at: %Schema{
          type: :string,
          format: :datetime,
          description: "When the command was created"
        },
        updated_at: %Schema{
          type: :string,
          format: :datetime,
          description: "When the command was last updated"
        }
      },
      required: [:id, :command_text, :inserted_at, :updated_at],
      example: %{
        id: "01234567-89ab-cdef-0123-456789abcdef",
        command_text: "ABC=value\necho $ABC\nsystemctl restart nginx",
        inserted_at: "2025-06-17T10:30:00Z",
        updated_at: "2025-06-17T10:30:00Z"
      }
    })
  end

  defmodule CommandPaginatedResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(
      CommonSchemas.paginated_response(
        CommandResponse,
        "Command Paginated Response",
        "Paginated list of commands with filtering and sorting metadata"
      )
    )
  end

  defmodule CommandSingleResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Command Single Response",
      description: "Single command response",
      type: :object,
      properties: %{
        data: CommandResponse
      },
      required: [:data],
      example: %{
        data: %{
          id: "01234567-89ab-cdef-0123-456789abcdef",
          command_text: "echo hello\ndate",
          inserted_at: "2025-06-17T12:00:00Z",
          updated_at: "2025-06-17T12:00:00Z"
        }
      }
    })
  end

  defmodule CommandCreateRequest do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Command Create Request",
      description: "Create a new command with target specification",
      type: :object,
      properties: %{
        command: %Schema{
          type: :object,
          properties: %{
            command_text: %Schema{
              type: :string,
              description: "Multi-line shell script/commands to execute",
              example: "ABC=value\necho $ABC\nsystemctl restart nginx"
            },
            target_nodes: %Schema{
              type: :array,
              items: %Schema{type: :string, format: :uuid},
              description: "Array of node UUIDs to target (required if target_all is false)",
              example: [
                "01234567-89ab-cdef-0123-456789abcdef",
                "fedcba98-7654-3210-fedc-ba9876543210"
              ]
            },
            target_all: %Schema{
              type: :boolean,
              description: "Whether to target all nodes (if true, target_nodes is ignored)",
              example: false,
              default: false
            }
          },
          required: [:command_text],
          example: %{
            command_text: "ABC=value\necho $ABC\nsystemctl restart nginx",
            target_nodes: [
              "01234567-89ab-cdef-0123-456789abcdef",
              "fedcba98-7654-3210-fedc-ba9876543210"
            ],
            target_all: false
          }
        }
      },
      required: [:command]
    })
  end
end
