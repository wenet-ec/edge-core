# edge_admin/lib/edge_admin_web/schemas/nodes/node_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.NodeSchemas do
  @moduledoc """
  OpenAPI schemas for Node resources
  """

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule NodeResponse do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "Node",
      description: "Edge node information",
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          format: :uuid,
          description: "Unique node identifier"
        },
        node_name: %Schema{
          type: :string,
          description: "Human-readable node name (derived from ID)",
          example: "node-01234567-89ab-cdef-0123-456789abcdef"
        },
        cluster_name: %Schema{
          type: :string,
          description: "Name of the cluster this node belongs to",
          pattern: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$",
          example: "prod-east"
        },
        netmaker_host_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "Netmaker Host UUID for API operations"
        },
        id_type: %Schema{
          type: :string,
          enum: ["persistent", "random"],
          description: "Type of node identifier (persistent or random)"
        },
        status: %Schema{
          type: :string,
          enum: ["healthy", "unhealthy", "unreachable"],
          description: "Current node status"
        },
        dns_hostname: %Schema{
          type: :string,
          description: "DNS hostname for this node",
          example: "node-01234567-89ab-cdef-0123-456789abcdef.cluster-abc.nm.internal"
        },
        http_port: %Schema{
          type: :integer,
          description: "HTTP API port"
        },
        ssh_port: %Schema{
          type: :integer,
          description: "SSH port"
        },
        host_metrics_port: %Schema{
          type: :integer,
          description: "Host metrics port (Node Exporter)"
        },
        wireguard_metrics_port: %Schema{
          type: :integer,
          description: "WireGuard metrics port (WireGuard Exporter)"
        },
        http_proxy_port: %Schema{
          type: :integer,
          description: "HTTP proxy port"
        },
        socks5_proxy_port: %Schema{
          type: :integer,
          description: "SOCKS5 proxy port"
        },
        api_token: %Schema{
          type: :string,
          description: "API token for agent authentication"
        },
        proxy_password: %Schema{
          type: :string,
          description: "Password for proxy authentication (username is always '_')"
        },
        version: %Schema{
          type: :string,
          nullable: true,
          description: "Agent version"
        },
        self_update_enabled: %Schema{
          type: :boolean,
          description: "Whether self-updates are enabled"
        },
        relay_enabled: %Schema{
          type: :boolean,
          description: "Whether relay gateway is required for connectivity"
        },
        last_seen_at: %Schema{
          type: :string,
          format: :datetime,
          nullable: true,
          description: "Last heartbeat timestamp from the node"
        },
        inserted_at: %Schema{
          type: :string,
          format: :datetime,
          description: "When the node was created"
        },
        updated_at: %Schema{
          type: :string,
          format: :datetime,
          description: "When the node was last updated"
        }
      },
      required: [
        :id,
        :cluster_name,
        :id_type,
        :http_port,
        :ssh_port,
        :host_metrics_port,
        :wireguard_metrics_port,
        :http_proxy_port,
        :socks5_proxy_port,
        :api_token,
        :proxy_password,
        :inserted_at,
        :updated_at
      ],
      example: %{
        id: "01234567-89ab-cdef-0123-456789abcdef",
        node_name: "node-01234567-89ab-cdef-0123-456789abcdef",
        cluster_name: "prod-east",
        netmaker_host_id: "def67890-5678-5678-5678-567890abcdef",
        id_type: "persistent",
        status: "healthy",
        dns_hostname: "node-01234567-89ab-cdef-0123-456789abcdef.cluster-prod-east.nm.internal",
        http_port: 44_000,
        ssh_port: 42_222,
        host_metrics_port: 49_100,
        wireguard_metrics_port: 49_586,
        http_proxy_port: 44_880,
        socks5_proxy_port: 44_180,
        api_token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
        proxy_password: "securepassword123",
        version: "0.1.0",
        self_update_enabled: false,
        relay_enabled: false,
        last_seen_at: "2025-06-09T08:20:00Z",
        inserted_at: "2025-06-09T08:00:00Z",
        updated_at: "2025-06-09T08:20:00Z"
      }
    })
  end

  defmodule NodeListResponse do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "Node List Response",
      description: "List of nodes",
      type: :object,
      properties: %{
        data: %Schema{
          type: :array,
          items: NodeResponse
        }
      },
      required: [:data],
      example: %{
        data: [
          %{
            id: "01234567-89ab-cdef-0123-456789abcdef",
            node_name: "node-01234567-89ab-cdef-0123-456789abcdef",
            cluster_id: "abc12345-1234-1234-1234-123456789abc",
            netmaker_host_id: "def67890-5678-5678-5678-567890abcdef",
            id_type: "persistent",
            status: "healthy",
            dns_hostname:
              "node-01234567-89ab-cdef-0123-456789abcdef.cluster-abc12345-1234-1234-1234-123456789abc.nm.internal",
            http_port: 44_000,
            ssh_port: 42_222,
            host_metrics_port: 49_100,
            wireguard_metrics_port: 49_586,
            http_proxy_port: 44_880,
            socks5_proxy_port: 44_180,
            api_token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
            proxy_password: "securepassword123",
            version: "0.1.0",
            self_update_enabled: false,
            last_seen_at: "2025-06-09T08:20:00Z",
            inserted_at: "2025-06-09T08:00:00Z",
            updated_at: "2025-06-09T08:20:00Z"
          }
        ]
      }
    })
  end

  defmodule NodePaginatedResponse do
    @moduledoc false

    OpenApiSpex.schema(
      CommonSchemas.paginated_response(
        NodeResponse,
        "Node Paginated Response",
        "Paginated list of nodes with filtering and sorting metadata"
      )
    )
  end

  defmodule NodeSingleResponse do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "Node Single Response",
      description: "Single node response",
      type: :object,
      properties: %{
        data: NodeResponse
      },
      required: [:data],
      example: %{
        data: %{
          id: "01234567-89ab-cdef-0123-456789abcdef",
          node_name: "node-01234567-89ab-cdef-0123-456789abcdef",
          cluster_id: "abc12345-1234-1234-1234-123456789abc",
          netmaker_host_id: "def67890-5678-5678-5678-567890abcdef",
          id_type: "persistent",
          status: "healthy",
          dns_hostname:
            "node-01234567-89ab-cdef-0123-456789abcdef.cluster-abc12345-1234-1234-1234-123456789abc.nm.internal",
          http_port: 44_000,
          ssh_port: 42_222,
          host_metrics_port: 49_100,
          wireguard_metrics_port: 49_586,
          http_proxy_port: 44_880,
          socks5_proxy_port: 44_180,
          api_token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
          proxy_password: "securepassword123",
          version: "0.1.0",
          self_update_enabled: false,
          last_seen_at: "2025-06-09T08:20:00Z",
          inserted_at: "2025-06-09T08:00:00Z",
          updated_at: "2025-06-09T08:20:00Z"
        }
      }
    })
  end

  defmodule ChangeClusterRequest do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "Change Cluster Request",
      description:
        "Request to move a node to a different cluster. " <>
          "Performs cluster migration via Netmaker (best-effort, reconciliation worker handles failures).",
      type: :object,
      properties: %{
        node: %Schema{
          type: :object,
          properties: %{
            cluster_name: %Schema{
              type: :string,
              pattern: "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$",
              description: "Name of the target cluster to move this node to.",
              example: "prod-west"
            }
          },
          required: [:cluster_name]
        }
      },
      required: [:node],
      example: %{
        node: %{
          cluster_name: "prod-west"
        }
      }
    })
  end
end
