# edge_admin/lib/edge_admin_web/schemas/nodes/node_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.NodeSchemas do
  @moduledoc """
  OpenAPI schemas for Node resources
  """

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule NodeResponse do
    @moduledoc false
    require OpenApiSpex

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
        cluster_id: %Schema{
          type: :string,
          format: :uuid,
          description: "Cluster this node belongs to"
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
          enum: ["online", "offline"],
          description: "Current node status"
        },
        dns_hostname: %Schema{
          type: :string,
          description: "DNS hostname for this node",
          example: "node-01234567-89ab-cdef-0123-456789abcdef.cluster-abc.nm.internal"
        },
        http_url: %Schema{
          type: :string,
          description: "HTTP URL for this node",
          example: "http://node-01234567-89ab-cdef-0123-456789abcdef.cluster-abc.nm.internal:44000"
        },
        http_port: %Schema{
          type: :integer,
          description: "HTTP API port"
        },
        ssh_port: %Schema{
          type: :integer,
          description: "SSH port"
        },
        metrics_port: %Schema{
          type: :integer,
          description: "Metrics port"
        },
        http_proxy_port: %Schema{
          type: :integer,
          description: "HTTP proxy port"
        },
        socks5_proxy_port: %Schema{
          type: :integer,
          description: "SOCKS5 proxy port"
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
      required: [:id, :cluster_id, :id_type, :http_port, :ssh_port, :metrics_port,
                 :http_proxy_port, :socks5_proxy_port, :inserted_at, :updated_at],
      example: %{
        id: "01234567-89ab-cdef-0123-456789abcdef",
        cluster_id: "abc12345-1234-1234-1234-123456789abc",
        netmaker_host_id: "def67890-5678-5678-5678-567890abcdef",
        id_type: "persistent",
        status: "online",
        dns_hostname: "node-01234567-89ab-cdef-0123-456789abcdef.cluster-abc12345-1234-1234-1234-123456789abc.nm.internal",
        http_url: "http://node-01234567-89ab-cdef-0123-456789abcdef.cluster-abc12345-1234-1234-1234-123456789abc.nm.internal:44000",
        http_port: 44000,
        ssh_port: 42222,
        metrics_port: 49100,
        http_proxy_port: 44880,
        socks5_proxy_port: 44180,
        version: "0.1.0",
        self_update_enabled: false,
        last_seen_at: "2025-06-09T08:20:00Z",
        inserted_at: "2025-06-09T08:00:00Z",
        updated_at: "2025-06-09T08:20:00Z"
      }
    })
  end

  defmodule NodeListResponse do
    @moduledoc false
    require OpenApiSpex

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
            cluster_id: "abc12345-1234-1234-1234-123456789abc",
            netmaker_host_id: "def67890-5678-5678-5678-567890abcdef",
            id_type: "persistent",
            status: "online",
            dns_hostname: "node-01234567-89ab-cdef-0123-456789abcdef.cluster-abc12345-1234-1234-1234-123456789abc.nm.internal",
            http_url: "http://node-01234567-89ab-cdef-0123-456789abcdef.cluster-abc12345-1234-1234-1234-123456789abc.nm.internal:44000",
            http_port: 44000,
            ssh_port: 42222,
            metrics_port: 49100,
            http_proxy_port: 44880,
            socks5_proxy_port: 44180,
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
    require OpenApiSpex

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
    require OpenApiSpex

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
          cluster_id: "abc12345-1234-1234-1234-123456789abc",
          netmaker_host_id: "def67890-5678-5678-5678-567890abcdef",
          id_type: "persistent",
          status: "online",
          dns_hostname: "node-01234567-89ab-cdef-0123-456789abcdef.cluster-abc12345-1234-1234-1234-123456789abc.nm.internal",
          http_url: "http://node-01234567-89ab-cdef-0123-456789abcdef.cluster-abc12345-1234-1234-1234-123456789abc.nm.internal:44000",
          http_port: 44000,
          ssh_port: 42222,
          metrics_port: 49100,
          http_proxy_port: 44880,
          socks5_proxy_port: 44180,
          version: "0.1.0",
          self_update_enabled: false,
          last_seen_at: "2025-06-09T08:20:00Z",
          inserted_at: "2025-06-09T08:00:00Z",
          updated_at: "2025-06-09T08:20:00Z"
        }
      }
    })
  end

  defmodule NodeUpdateRequest do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Update Node Request",
      description: "Request to update an existing node",
      type: :object,
      properties: %{
        node: %Schema{
          type: :object,
          properties: %{
            cluster_id: %Schema{
              type: :string,
              format: :uuid,
              nullable: true,
              description: "Cluster this node belongs to"
            },
            netmaker_host_id: %Schema{
              type: :string,
              format: :uuid,
              nullable: true,
              description: "Netmaker Host UUID"
            },
            status: %Schema{
              type: :string,
              nullable: true,
              enum: ["online", "offline"],
              description: "Node status"
            },
            api_token: %Schema{
              type: :string,
              nullable: true,
              description: "API authentication token"
            },
            proxy_password: %Schema{
              type: :string,
              nullable: true,
              description: "Proxy authentication password"
            },
            version: %Schema{
              type: :string,
              nullable: true,
              description: "Agent version"
            },
            self_update_enabled: %Schema{
              type: :boolean,
              nullable: true,
              description: "Whether self-updates are enabled"
            },
            last_seen_at: %Schema{
              type: :string,
              format: :datetime,
              nullable: true,
              description: "Last heartbeat timestamp"
            }
          }
        }
      },
      required: [:node],
      example: %{
        node: %{
          status: "offline",
          last_seen_at: "2025-06-09T08:25:00Z"
        }
      }
    })
  end
end
