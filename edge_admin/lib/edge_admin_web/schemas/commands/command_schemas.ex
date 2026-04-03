# edge_admin/lib/edge_admin_web/schemas/commands/command_schemas.ex
defmodule EdgeAdminWeb.Schemas.Commands.CommandSchemas do
  @moduledoc """
  OpenAPI schemas for Command resources
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule CommandResponse do
    @moduledoc false

    schema(%{
      title: "CommandResponse",
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
        timeout: %Schema{
          type: :integer,
          nullable: true,
          description: "Command timeout in milliseconds (optional, null means no timeout)",
          example: 30_000
        },
        targeting: %Schema{
          type: :object,
          description: "Targeting configuration used when creating this command (informational only, not filterable)",
          example: %{
            type: "nodes",
            node_ids: ["01234567-89ab-cdef-0123-456789abcdef"],
            node_filters: %{status: "healthy"}
          }
        },
        inserted_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the command was created"
        },
        updated_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the command was last updated"
        }
      },
      required: [:id, :command_text, :targeting, :inserted_at, :updated_at],
      example: %{
        id: "01234567-89ab-cdef-0123-456789abcdef",
        command_text: "ABC=value\necho $ABC\nsystemctl restart nginx",
        timeout: 30_000,
        targeting: %{
          type: "nodes",
          node_ids: ["01234567-89ab-cdef-0123-456789abcdef"],
          node_filters: %{status: "healthy"}
        },
        inserted_at: "2025-06-17T10:30:00Z",
        updated_at: "2025-06-17T10:30:00Z"
      }
    })
  end

  defmodule CommandPaginatedResponse do
    @moduledoc false

    schema(
      CommonSchemas.paginated_response(
        CommandResponse,
        "CommandPaginatedResponse",
        "Paginated list of commands with filtering and sorting metadata"
      )
    )
  end

  defmodule CommandSingleResponse do
    @moduledoc false

    schema(%{
      title: "CommandSingleResponse",
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
          timeout: nil,
          targeting: %{
            type: "all",
            node_filters: %{status: "healthy"}
          },
          inserted_at: "2025-06-17T12:00:00Z",
          updated_at: "2025-06-17T12:00:00Z"
        }
      }
    })
  end

  defmodule CommandCreateRequest do
    @moduledoc false

    schema(%{
      title: "CommandCreateRequest",
      description: "Create a new command with flexible targeting options",
      type: :object,
      properties: %{
        command: %Schema{
          type: :object,
          properties: %{
            command_text: %Schema{
              type: :string,
              minLength: 1,
              description: "Multi-line shell script/commands to execute",
              example: "ABC=value\necho $ABC\nsystemctl restart nginx"
            },
            timeout: %Schema{
              type: :integer,
              nullable: true,
              minimum: 1,
              description: "Command timeout in milliseconds (optional, null or omitted means no timeout, must be > 0)",
              example: 30_000
            },
            targeting: %Schema{
              type: :object,
              properties: %{
                type: %Schema{
                  type: :string,
                  enum: ["all", "nodes", "clusters"],
                  description:
                    "Targeting strategy: 'all' for all nodes, 'nodes' for specific nodes, 'clusters' for specific clusters"
                },
                node_ids: %Schema{
                  type: :array,
                  items: %Schema{type: :string, format: :uuid},
                  description: "Array of node IDs (required when type is 'nodes') (will always be deduplicated)",
                  example: [
                    "01234567-89ab-cdef-0123-456789abcdef",
                    "fedcba98-7654-3210-fedc-ba9876543210"
                  ]
                },
                cluster_names: %Schema{
                  type: :array,
                  items: %Schema{type: :string},
                  description:
                    "Array of cluster names (required when type is 'clusters') (will always be deduplicated)",
                  example: ["prod", "staging"]
                },
                node_filters: %Schema{
                  type: :object,
                  description:
                    "Optional filters to apply to target nodes (AND logic with cluster_filters). Supports all node list filters except cluster_name.",
                  properties: %{
                    id_type: %Schema{
                      type: :string,
                      enum: ["persistent", "random"],
                      description: "Filter by node ID type"
                    },
                    status: %Schema{
                      type: :string,
                      enum: ["healthy", "unhealthy", "unreachable"],
                      description: "Filter by node status"
                    },
                    cluster_name: %Schema{
                      type: :string,
                      description: "Filter by cluster name (exact match or wildcard: prod*, *staging, etc.)"
                    },
                    version: %Schema{
                      type: :string,
                      description: "Filter by node version (exact match or wildcard: 1.0.0, 1.*, etc.)"
                    },
                    self_update_enabled: %Schema{
                      type: :boolean,
                      description: "Filter by self-update enabled status"
                    },
                    last_seen_at__gte: %Schema{
                      anyOf: [
                        %Schema{type: :string, format: :"date-time"},
                        %Schema{type: :string, format: :date}
                      ],
                      description: "Filter nodes last seen after or on this datetime"
                    },
                    last_seen_at__lte: %Schema{
                      anyOf: [
                        %Schema{type: :string, format: :"date-time"},
                        %Schema{type: :string, format: :date}
                      ],
                      description: "Filter nodes last seen before or on this datetime"
                    },
                    inserted_at__gte: %Schema{
                      anyOf: [
                        %Schema{type: :string, format: :"date-time"},
                        %Schema{type: :string, format: :date}
                      ],
                      description: "Filter nodes inserted after or on this date"
                    },
                    inserted_at__lte: %Schema{
                      anyOf: [
                        %Schema{type: :string, format: :"date-time"},
                        %Schema{type: :string, format: :date}
                      ],
                      description: "Filter nodes inserted before or on this date"
                    },
                    updated_at__gte: %Schema{
                      anyOf: [
                        %Schema{type: :string, format: :"date-time"},
                        %Schema{type: :string, format: :date}
                      ],
                      description: "Filter nodes updated after or on this datetime"
                    },
                    updated_at__lte: %Schema{
                      anyOf: [
                        %Schema{type: :string, format: :"date-time"},
                        %Schema{type: :string, format: :date}
                      ],
                      description: "Filter nodes updated before or on this datetime"
                    }
                  },
                  additionalProperties: false
                },
                cluster_filters: %Schema{
                  type: :object,
                  description:
                    "Optional filters to apply to target clusters (AND logic with node_filters). Supports all cluster list filters.",
                  properties: %{
                    name: %Schema{
                      type: :string,
                      description: "Filter by cluster name (exact match or wildcard: prod*, *staging, etc.)"
                    },
                    ipv4_range: %Schema{
                      type: :string,
                      description: "Filter by IPv4 range (CIDR notation)"
                    },
                    node_count: %Schema{
                      type: :integer,
                      description: "Filter by exact node count"
                    },
                    node_count__gte: %Schema{
                      type: :integer,
                      description: "Filter by node count greater than or equal to"
                    },
                    node_count__lte: %Schema{
                      type: :integer,
                      description: "Filter by node count less than or equal to"
                    },
                    has_node_limit: %Schema{
                      type: :boolean,
                      description: "Filter clusters that have (true) or do not have (false) a node limit set"
                    },
                    inserted_at__gte: %Schema{
                      anyOf: [
                        %Schema{type: :string, format: :"date-time"},
                        %Schema{type: :string, format: :date}
                      ],
                      description: "Filter clusters inserted after or on this date"
                    },
                    inserted_at__lte: %Schema{
                      anyOf: [
                        %Schema{type: :string, format: :"date-time"},
                        %Schema{type: :string, format: :date}
                      ],
                      description: "Filter clusters inserted before or on this date"
                    },
                    updated_at__gte: %Schema{
                      anyOf: [
                        %Schema{type: :string, format: :"date-time"},
                        %Schema{type: :string, format: :date}
                      ],
                      description: "Filter clusters updated after or on this datetime"
                    },
                    updated_at__lte: %Schema{
                      anyOf: [
                        %Schema{type: :string, format: :"date-time"},
                        %Schema{type: :string, format: :date}
                      ],
                      description: "Filter clusters updated before or on this datetime"
                    }
                  },
                  additionalProperties: false
                }
              },
              required: [:type],
              example: %{
                type: "clusters",
                cluster_names: ["prod", "staging"],
                cluster_filters: %{
                  name: "*prod*"
                },
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
