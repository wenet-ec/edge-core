# edge_admin/lib/edge_admin_web/schemas/nodes/node_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.NodeSchemas do
  @moduledoc """
  OpenAPI schemas for Node resources
  """

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
        hardware_id: %Schema{
          type: :string,
          description: "Hardware identifier (MAC address hash or hostname+timestamp+random)",
          example: "hw-123-abc-456"
        },
        vpn_ip: %Schema{
          type: :string,
          nullable: true,
          description: "VPN-assigned IP address",
          example: "100.64.0.1"
        },
        vpn_hostname: %Schema{
          type: :string,
          nullable: true,
          description: "VPN hostname (computed from node ID)",
          example: "node-01234567-89ab-cdef-0123-456789abcdef"
        },
        last_seen_at: %Schema{
          type: :string,
          format: :datetime,
          nullable: true,
          description: "Last heartbeat timestamp from the node"
        },
        status: %Schema{
          type: :string,
          nullable: true,
          enum: ["online", "offline", "unknown"],
          description: "Current node status"
        }
      },
      required: [:id, :hardware_id],
      example: %{
        id: "01234567-89ab-cdef-0123-456789abcdef",
        hardware_id: "hw-123-abc-456",
        vpn_ip: "100.64.0.1",
        vpn_hostname: "node-01234567-89ab-cdef-0123-456789abcdef",
        last_seen_at: "2025-06-09T08:20:00Z",
        status: "online"
      }
    })
  end

  defmodule NodeListResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Node List",
      description: "List of edge nodes",
      type: :object,
      properties: %{
        data: %Schema{
          type: :array,
          items: NodeResponse,
          description: "Array of nodes"
        }
      },
      required: [:data],
      example: %{
        data: [
          %{
            id: "01234567-89ab-cdef-0123-456789abcdef",
            hardware_id: "hw-123-abc-456",
            vpn_ip: "100.64.0.1",
            vpn_hostname: "node-01234567-89ab-cdef-0123-456789abcdef",
            last_seen_at: "2025-06-09T08:20:00Z",
            status: "online"
          }
        ]
      }
    })
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
          hardware_id: "hw-123-abc-456",
          vpn_ip: "100.64.0.1",
          vpn_hostname: "node-01234567-89ab-cdef-0123-456789abcdef",
          last_seen_at: "2025-06-09T08:20:00Z",
          status: "online"
        }
      }
    })
  end

  defmodule NodeCreateRequest do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Create Node Request",
      description: "Request to create a new node",
      type: :object,
      properties: %{
        node: %Schema{
          type: :object,
          properties: %{
            hardware_id: %Schema{
              type: :string,
              description: "Hardware identifier (required)",
              example: "hw-123-abc-456"
            },
            vpn_ip: %Schema{
              type: :string,
              nullable: true,
              description: "VPN-assigned IP address (optional)",
              example: "100.64.0.1"
            },
            last_seen_at: %Schema{
              type: :string,
              format: :datetime,
              nullable: true,
              description: "Last heartbeat timestamp (optional)"
            },
            status: %Schema{
              type: :string,
              nullable: true,
              enum: ["online", "offline", "unknown"],
              description: "Node status (optional)"
            }
          },
          required: [:hardware_id]
        }
      },
      required: [:node],
      example: %{
        node: %{
          hardware_id: "hw-123-abc-456",
          vpn_ip: "100.64.0.1",
          status: "online"
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
            hardware_id: %Schema{
              type: :string,
              description: "Hardware identifier",
              example: "hw-123-abc-456"
            },
            vpn_ip: %Schema{
              type: :string,
              nullable: true,
              description: "VPN-assigned IP address",
              example: "100.64.0.1"
            },
            last_seen_at: %Schema{
              type: :string,
              format: :datetime,
              nullable: true,
              description: "Last heartbeat timestamp"
            },
            status: %Schema{
              type: :string,
              nullable: true,
              enum: ["online", "offline", "unknown"],
              description: "Node status"
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
