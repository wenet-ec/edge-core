# edge_admin/lib/edge_admin_web/schemas/self_updates/self_update_request_schemas.ex
defmodule EdgeAdminWeb.Schemas.SelfUpdates.SelfUpdateRequestSchemas do
  @moduledoc """
  OpenAPI schemas for SelfUpdateRequest resources
  """

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule SelfUpdateRequestResponse do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "SelfUpdateRequest",
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
          format: :datetime,
          description: "When the request was created"
        },
        updated_at: %Schema{
          type: :string,
          format: :datetime,
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

    OpenApiSpex.schema(
      CommonSchemas.paginated_response(
        SelfUpdateRequestResponse,
        "SelfUpdateRequest Paginated Response",
        "Paginated list of self-update requests"
      )
    )
  end

  defmodule SelfUpdateRequestSingleResponse do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "SelfUpdateRequest Single Response",
      description: "Single self-update request response",
      type: :object,
      properties: %{
        data: SelfUpdateRequestResponse
      },
      required: [:data],
      example: %{
        data: %{
          id: "01234567-89ab-cdef-0123-456789abcdef",
          targeting: %{
            type: "clusters",
            cluster_names: ["prod", "staging"]
          },
          status: "completed",
          summary: %{
            total: 25,
            triggered: 23,
            failed: 2
          },
          inserted_at: "2025-06-17T10:30:00Z",
          updated_at: "2025-06-17T10:35:00Z"
        }
      }
    })
  end

  defmodule SelfUpdateRequestCreateRequest do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "SelfUpdateRequest Create Request",
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
              description: "Additional node filters"
            },
            cluster_filters: %Schema{
              type: :object,
              description: "Additional cluster filters"
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
