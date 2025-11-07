# edge_admin_web/lib/edge_admin_web/schemas/nodes/cluster_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.ClusterSchemas do
  @moduledoc """
  OpenAPI schemas for Cluster resources
  """

  alias OpenApiSpex.Schema

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
          description: "Unique cluster identifier"
        },
        name: %Schema{
          type: :string,
          description: "Cluster name (max 24 chars)",
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
        :network_name,
        :dns_domain,
        :inserted_at,
        :updated_at
      ],
      example: %{
        id: "abc12345-1234-1234-1234-123456789abc",
        name: "prod-east",
        ipv4_range: "100.64.0.0/24",
        node_count: 5,
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
          node_count: 5,
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
              description: "Cluster name (max 24 chars, auto-generated 12-char alphanumeric if not provided)",
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
