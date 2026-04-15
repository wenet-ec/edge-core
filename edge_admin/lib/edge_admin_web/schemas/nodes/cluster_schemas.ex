# edge_admin_web/lib/edge_admin_web/schemas/nodes/cluster_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.ClusterSchemas do
  @moduledoc """
  OpenAPI schemas for Cluster resources
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule NodeSummary do
    @moduledoc false

    schema(%{
      title: "NodeSummary",
      description: "Brief node information within cluster response",
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          description: "Node ID",
          example: "abc12345-1234-1234-1234-123456789abc"
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
          enum: ["persistent", "random"],
          example: "persistent"
        },
        vpn_hostname: %Schema{
          type: :string,
          description: "DNS hostname for this node",
          example: "node-abc12345-1234-1234-1234-123456789abc.cluster-prod-east.nm.internal"
        }
      },
      required: [:id, :status, :id_type, :vpn_hostname],
      example: %{
        id: "abc12345-1234-1234-1234-123456789abc",
        status: "healthy",
        id_type: "persistent",
        vpn_hostname: "node-abc12345-1234-1234-1234-123456789abc.cluster-prod-east.nm.internal"
      }
    })
  end

  defmodule ClusterResponse do
    @moduledoc false

    schema(%{
      title: "ClusterResponse",
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
          description:
            "Cluster name - primary identifier used in API operations (max 24 chars, alphanumeric with hyphens)",
          pattern: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$",
          example: "prod-east"
        },
        ipv4_range: %Schema{
          type: :string,
          description: "IPv4 CIDR range for this cluster",
          example: "100.64.0.0/24"
        },
        node_limit: %Schema{
          type: :integer,
          nullable: true,
          description: "Maximum number of nodes allowed in this cluster (null means no limit enforced)"
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
        vpn_domain: %Schema{
          type: :string,
          description: "DNS domain suffix for nodes in this cluster",
          example: "cluster-prod-east.nm.internal"
        },
        inserted_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the cluster was created"
        },
        updated_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the cluster was last updated"
        }
      },
      required: [
        :id,
        :name,
        :ipv4_range,
        :node_limit,
        :node_count,
        :nodes,
        :network_name,
        :vpn_domain,
        :inserted_at,
        :updated_at
      ],
      example: %{
        id: "abc12345-1234-1234-1234-123456789abc",
        name: "prod-east",
        ipv4_range: "100.64.0.0/24",
        node_limit: 50,
        node_count: 2,
        nodes: [
          %{
            id: "abc12345-1234-1234-1234-123456789abc",
            status: "healthy",
            id_type: "persistent",
            vpn_hostname: "node-abc12345-1234-1234-1234-123456789abc.cluster-prod-east.nm.internal"
          },
          %{
            id: "def67890-5678-5678-5678-567890abcdef",
            status: "healthy",
            id_type: "persistent",
            vpn_hostname: "node-def67890-5678-5678-5678-567890abcdef.cluster-prod-east.nm.internal"
          }
        ],
        network_name: "cluster-prod-east",
        vpn_domain: "cluster-prod-east.nm.internal",
        inserted_at: "2025-06-09T08:00:00Z",
        updated_at: "2025-06-09T08:00:00Z"
      }
    })
  end

  defmodule ClusterPaginatedResponse do
    @moduledoc false

    schema(
      CommonSchemas.paginated_response(
        ClusterResponse,
        "ClusterPaginatedResponse",
        "Paginated list of clusters with metadata"
      )
    )
  end

  defmodule ClusterSingleResponse do
    @moduledoc false

    schema(CommonSchemas.single_response(ClusterResponse, "ClusterSingleResponse", "Single cluster response"))
  end

  defmodule ClusterUpdateRequest do
    @moduledoc false

    schema(%{
      title: "ClusterUpdateRequest",
      description:
        "Parameters for updating a cluster. Only provided fields are updated. Pass null to unset a nullable field.",
      type: :object,
      properties: %{
        node_limit: %Schema{
          type: :integer,
          nullable: true,
          description: "Maximum nodes allowed in this cluster (null means no limit enforced)",
          minimum: 1,
          example: 50
        }
      },
      example: %{node_limit: 50}
    })
  end

  defmodule ClusterCreateRequest do
    @moduledoc false

    schema(%{
      title: "ClusterCreateRequest",
      description: "Parameters for creating a new cluster",
      type: :object,
      properties: %{
        name: %Schema{
          type: :string,
          description: "Cluster name — primary identifier (max 24 chars, lowercase alphanumeric + hyphens)",
          pattern: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$",
          maxLength: 24,
          example: "prod-east"
        },
        ipv4_range: %Schema{
          type: :string,
          nullable: true,
          pattern: "^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\/\\d{1,2}$",
          description: "IPv4 CIDR range (auto-generated if not provided)",
          example: "100.64.0.0/24"
        },
        node_limit: %Schema{
          type: :integer,
          nullable: true,
          description: "Maximum nodes allowed in this cluster (null means no limit enforced)",
          minimum: 1,
          example: 50
        }
      },
      required: [:name],
      example: %{
        name: "prod-east",
        ipv4_range: "100.64.1.0/24",
        node_limit: 50
      }
    })
  end
end
