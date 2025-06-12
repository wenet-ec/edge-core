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
          description: "Unique node identifier (hardware ID)"
        },
        id_type: %Schema{
          type: :string,
          nullable: true,
          enum: ["machine_id", "hardware_id", "temporary_id"],
          description: "Type of node identifier used for determining persistence"
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
      required: [:id],
      example: %{
        id: "01234567-89ab-cdef-0123-456789abcdef",
        id_type: "machine_id",
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
            id_type: "machine_id",
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
          id_type: "machine_id",
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
      title: "Node Create Request",
      description: "Parameters for creating a new node",
      type: :object,
      properties: %{
        node: %Schema{
          type: :object,
          properties: %{
            id: %Schema{
              type: :string,
              description: "Hardware ID of the node (will be converted to UUID format)",
              example: "bc9ebeb196a44dfd953e899a61637577"
            },
            id_type: %Schema{
              type: :string,
              enum: ["machine_id", "hardware_id", "temporary_id"],
              description: "Type of identifier being provided"
            },
            vpn_ip: %Schema{
              type: :string,
              nullable: true,
              description: "VPN-assigned IP address",
              example: "100.64.0.1"
            },
            status: %Schema{
              type: :string,
              nullable: true,
              enum: ["online", "offline", "unknown"],
              description: "Initial node status"
            }
          },
          required: [:id, :id_type],
          example: %{
            id: "bc9ebeb196a44dfd953e899a61637577",
            id_type: "machine_id",
            status: "online"
          }
        }
      },
      required: [:node]
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
