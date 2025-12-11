# edge_admin/lib/edge_admin_web/schemas/commands/command_schemas.ex
defmodule EdgeAdminWeb.Schemas.Commands.CommandSchemas do
  @moduledoc """
  OpenAPI schemas for Command resources
  """

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

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
      description: "Create a new command with flexible targeting options",
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
            targeting: %Schema{
              type: :object,
              properties: %{
                type: %Schema{
                  type: :string,
                  enum: ["all", "nodes"],
                  description: "Targeting strategy: 'all' for all nodes, 'nodes' for specific nodes"
                },
                node_ids: %Schema{
                  type: :array,
                  items: %Schema{type: :string, format: :uuid},
                  description:
                    "Array of node IDs (required when type is 'nodes') (will always be deduplicated)",
                  example: [
                    "01234567-89ab-cdef-0123-456789abcdef",
                    "fedcba98-7654-3210-fedc-ba9876543210"
                  ]
                },
                node_filters: %Schema{
                  type: :object,
                  description: "Optional filters to apply to target nodes",
                  properties: %{
                    status: %Schema{
                      type: :string,
                      enum: ["healthy", "unhealthy", "unreachable"],
                      description: "Filter by node status"
                    },
                    id_type: %Schema{
                      type: :string,
                      enum: ["persistent", "random"],
                      description: "Filter by node ID type"
                    },
                    cluster_id: %Schema{
                      type: :string,
                      format: :uuid,
                      description: "Filter by cluster ID"
                    }
                  },
                  additionalProperties: false
                }
              },
              required: [:type],
              example: %{
                type: "all",
                node_filters: %{
                  status: "healthy",
                  id_type: "persistent"
                }
              }
            }
          },
          required: [:command_text, :targeting],
          example: %{
            command_text: "ABC=value\necho $ABC\nsudo docker ps",
            targeting: %{
              type: "nodes",
              node_ids: ["01234567-89ab-cdef-0123-456789abcdef"],
              node_filters: %{
                status: "healthy",
                id_type: "persistent"
              }
            }
          }
        }
      },
      required: [:command]
    })
  end
end
