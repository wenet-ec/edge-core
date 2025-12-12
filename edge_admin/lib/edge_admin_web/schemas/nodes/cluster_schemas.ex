# edge_admin_web/lib/edge_admin_web/schemas/nodes/cluster_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.ClusterSchemas do
  @moduledoc """
  OpenAPI schemas for Cluster resources
  """

  alias OpenApiSpex.Schema

  defmodule NodeSummary do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Node Summary",
      description: "Brief node information within cluster response",
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          description: "Node ID",
          example: "node-abc123"
        },
        status: %Schema{
          type: :string,
          description: "Node status",
          enum: ["healthy", "unhealthy"],
          example: "healthy"
        },
        id_type: %Schema{
          type: :string,
          description: "Node ID type",
          enum: ["hostname", "mac"],
          example: "hostname"
        },
        dns_hostname: %Schema{
          type: :string,
          description: "DNS hostname for this node",
          example: "node-abc123.cluster-prod-east.nm.internal"
        }
      },
      required: [:id, :status, :id_type, :dns_hostname],
      example: %{
        id: "node-abc123",
        status: "healthy",
        id_type: "hostname",
        dns_hostname: "node-abc123.cluster-prod-east.nm.internal"
      }
    })
  end

  defmodule ClusterResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Cluster",
      description: "Edge cluster information",
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          format: :uuid,
          description: "Unique cluster identifier (UUID for database compatibility, use name for API operations)"
        },
        name: %Schema{
          type: :string,
          description: "Cluster name - primary identifier used in API operations (max 24 chars, alphanumeric with hyphens)",
          pattern: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$",
          example: "prod-east"
        },
        ipv4_range: %Schema{
          type: :string,
          description: "IPv4 CIDR range for this cluster",
          example: "100.64.0.0/24"
        },
        node_count: %Schema{
          type: :integer,
          description: "Number of nodes in this cluster"
        },
        nodes: %Schema{
          type: :array,
          description: "Summary of nodes in this cluster",
          items: NodeSummary
        },
        network_name: %Schema{
          type: :string,
          description: "Netmaker network name",
          example: "cluster-prod-east"
        },
        dns_domain: %Schema{
          type: :string,
          description: "DNS domain suffix for nodes in this cluster",
          example: "cluster-prod-east.nm.internal"
        },
        inserted_at: %Schema{
          type: :string,
          format: :datetime,
          description: "When the cluster was created"
        },
        updated_at: %Schema{
          type: :string,
          format: :datetime,
          description: "When the cluster was last updated"
        }
      },
      required: [
        :id,
        :name,
        :ipv4_range,
        :node_count,
        :nodes,
        :network_name,
        :dns_domain,
        :inserted_at,
        :updated_at
      ],
      example: %{
        id: "abc12345-1234-1234-1234-123456789abc",
        name: "prod-east",
        ipv4_range: "100.64.0.0/24",
        node_count: 2,
        nodes: [
          %{
            id: "node-abc123",
            status: "healthy",
            id_type: "hostname",
            dns_hostname: "node-abc123.cluster-prod-east.nm.internal"
          },
          %{
            id: "node-def456",
            status: "healthy",
            id_type: "hostname",
            dns_hostname: "node-def456.cluster-prod-east.nm.internal"
          }
        ],
        network_name: "cluster-prod-east",
        dns_domain: "cluster-prod-east.nm.internal",
        inserted_at: "2025-06-09T08:00:00Z",
        updated_at: "2025-06-09T08:00:00Z"
      }
    })
  end

  defmodule ClusterPaginatedResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(
      EdgeAdminWeb.Schemas.CommonSchemas.paginated_response(
        ClusterResponse,
        "Cluster Paginated Response",
        "Paginated list of clusters with metadata"
      )
    )
  end

  defmodule ClusterSingleResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Cluster Single Response",
      description: "Single cluster response",
      type: :object,
      properties: %{
        data: ClusterResponse
      },
      required: [:data],
      example: %{
        data: %{
          id: "abc12345-1234-1234-1234-123456789abc",
          name: "prod-east",
          ipv4_range: "100.64.0.0/24",
          node_count: 2,
          nodes: [
            %{
              id: "node-abc123",
              status: "healthy",
              id_type: "hostname",
              dns_hostname: "node-abc123.cluster-prod-east.nm.internal"
            },
            %{
              id: "node-def456",
              status: "healthy",
              id_type: "hostname",
              dns_hostname: "node-def456.cluster-prod-east.nm.internal"
            }
          ],
          network_name: "cluster-prod-east",
          dns_domain: "cluster-prod-east.nm.internal",
          inserted_at: "2025-06-09T08:00:00Z",
          updated_at: "2025-06-09T08:00:00Z"
        }
      }
    })
  end

  defmodule ClusterCreateRequest do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Cluster Create Request",
      description: "Parameters for creating a new cluster (all fields optional for auto-generation)",
      type: :object,
      properties: %{
        cluster: %Schema{
          type: :object,
          properties: %{
            name: %Schema{
              type: :string,
              nullable: true,
              description: "Cluster name - will be used as primary identifier (max 24 chars, auto-generated 12-char alphanumeric if not provided)",
              pattern: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$",
              example: "prod-east"
            },
            ipv4_range: %Schema{
              type: :string,
              nullable: true,
              description: "IPv4 CIDR range (auto-generated if not provided)",
              example: "100.64.0.0/24"
            }
          },
          example: %{
            name: "prod-east",
            ipv4_range: "100.64.1.0/24"
          }
        }
      },
      required: [:cluster]
    })
  end
end
