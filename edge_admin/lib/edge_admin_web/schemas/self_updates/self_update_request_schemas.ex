# edge_admin/lib/edge_admin_web/schemas/self_updates/self_update_request_schemas.ex
defmodule EdgeAdminWeb.Schemas.SelfUpdates.SelfUpdateRequestSchemas do
  @moduledoc """
  OpenAPI schemas for SelfUpdateRequest resources
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule SelfUpdateRequestResponse do
    @moduledoc false

    schema(%{
      title: "SelfUpdateRequestResponse",
      description: "Self-update request information",
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          format: :uuid,
          description: "Unique request identifier"
        },
        targeting: %Schema{
          type: :object,
          description: "Targeting configuration (same format as commands)",
          example: %{
            type: "all",
            node_filters: %{
              status: "healthy",
              self_update_enabled: true
            }
          }
        },
        status: %Schema{
          type: :string,
          enum: ["pending", "processing", "completed"],
          description: "Request processing status"
        },
        summary: %Schema{
          type: :object,
          nullable: true,
          description: "Summary of results (available after completion)",
          properties: %{
            total: %Schema{type: :integer, description: "Total nodes targeted"},
            triggered: %Schema{type: :integer, description: "Nodes where update was triggered"},
            failed: %Schema{type: :integer, description: "Nodes where update failed"}
          },
          example: %{
            total: 10,
            triggered: 8,
            failed: 2
          }
        },
        inserted_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the request was created"
        },
        updated_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the request was last updated"
        }
      },
      required: [:id, :targeting, :status, :inserted_at, :updated_at],
      example: %{
        id: "01234567-89ab-cdef-0123-456789abcdef",
        targeting: %{
          type: "all",
          node_filters: %{
            status: "healthy",
            self_update_enabled: true
          }
        },
        status: "completed",
        summary: %{
          total: 10,
          triggered: 8,
          failed: 2
        },
        inserted_at: "2025-06-17T10:30:00Z",
        updated_at: "2025-06-17T10:35:00Z"
      }
    })
  end

  defmodule SelfUpdateRequestPaginatedResponse do
    @moduledoc false

    schema(
      CommonSchemas.paginated_response(
        SelfUpdateRequestResponse,
        "SelfUpdateRequestPaginatedResponse",
        "Paginated list of self-update requests"
      )
    )
  end

  defmodule SelfUpdateRequestSingleResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(
        SelfUpdateRequestResponse,
        "SelfUpdateRequestSingleResponse",
        "Single self-update request response"
      )
    )
  end

  defmodule SelfUpdateRequestCreateRequest do
    @moduledoc false

    schema(%{
      title: "SelfUpdateRequestCreateRequest",
      description: """
      Create a new self-update request.

      Uses the same targeting system as commands. Only healthy nodes with self_update_enabled=true will be updated.
      """,
      type: :object,
      properties: %{
        targeting: %Schema{
          type: :object,
          description: "Targeting specification",
          properties: %{
            type: %Schema{
              type: :string,
              enum: ["all", "nodes", "clusters"],
              description: "Targeting type"
            },
            node_ids: %Schema{
              type: :array,
              items: %Schema{type: :string, format: :uuid},
              description: "Node IDs (required if type is 'nodes')"
            },
            cluster_names: %Schema{
              type: :array,
              items: %Schema{type: :string},
              description: "Cluster names (required if type is 'clusters')"
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
          required: [:type]
        }
      },
      required: [:targeting],
      example: %{
        targeting: %{
          type: "all",
          node_filters: %{
            version: "0.1.*"
          }
        }
      }
    })
  end
end
