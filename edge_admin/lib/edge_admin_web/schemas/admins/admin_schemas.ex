# edge_admin/lib/edge_admin_web/schemas/admins/admin_schemas.ex
defmodule EdgeAdminWeb.Schemas.Admins.AdminSchemas do
  @moduledoc """
  OpenAPI schemas for admin metadata endpoints.
  """

  alias OpenApiSpex.Schema

  defmodule AdminResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Admin Response",
      description: "This admin's identity and configuration",
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          description: "Admin ID (e.g., k7m3n2p9x4j6)"
        },
        name: %Schema{
          type: :string,
          description: "Admin name (e.g., admin-k7m3n2p9x4j6)"
        },
        max_capacity: %Schema{
          type: :integer,
          description: "Maximum node capacity for this admin"
        },
        erlang_node_name: %Schema{
          type: :string,
          description: "Erlang distribution node name"
        },
        dns_hostname: %Schema{
          type: :string,
          description: "DNS hostname for this admin"
        },
        admin_cluster_name: %Schema{
          type: :string,
          description: "Name of the admin cluster this admin belongs to"
        },
        last_computed_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "Last time metadata was computed",
          nullable: true
        }
      },
      required: [:id, :name, :max_capacity, :erlang_node_name, :dns_hostname, :admin_cluster_name],
      example: %{
        id: "k7m3n2p9x4j6",
        name: "admin-k7m3n2p9x4j6",
        max_capacity: 200,
        erlang_node_name: "admin@admin-k7m3n2p9x4j6.admin-cluster-1.nm.internal",
        dns_hostname: "admin-k7m3n2p9x4j6.admin-cluster-1.nm.internal",
        admin_cluster_name: "admin-cluster-1",
        last_computed_at: "2025-01-15T12:00:00Z"
      }
    })
  end

  defmodule AdminTopologyEntry do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Admin Topology Entry",
      description: "A peer admin in the cluster topology",
      type: :object,
      properties: %{
        name: %Schema{
          type: :string,
          description: "Admin name (e.g., admin-k7m3n2p9x4j6)"
        },
        max_capacity: %Schema{
          type: :integer,
          description: "Maximum node capacity"
        },
        erlang_node_name: %Schema{
          type: :string,
          description: "Erlang distribution node name"
        }
      },
      required: [:name, :max_capacity, :erlang_node_name],
      example: %{
        name: "admin-k7m3n2p9x4j6",
        max_capacity: 200,
        erlang_node_name: "admin@admin-k7m3n2p9x4j6.admin-cluster-1.nm.internal"
      }
    })
  end

  defmodule AdminClusterResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Admin Cluster Response",
      description: "Admin cluster topology and state",
      type: :object,
      properties: %{
        name: %Schema{
          type: :string,
          description: "Admin cluster name"
        },
        total_admins: %Schema{
          type: :integer,
          description: "Total number of admins in the cluster"
        },
        degraded: %Schema{
          type: :boolean,
          description: "Whether the cluster is in degraded mode (capacity exceeded)"
        },
        topology: %Schema{
          type: :array,
          items: AdminTopologyEntry,
          description: "List of all admins in the cluster"
        }
      },
      required: [:name, :total_admins, :degraded, :topology],
      example: %{
        name: "admin-cluster-1",
        total_admins: 2,
        degraded: false,
        topology: [
          %{
            name: "admin-k7m3n2p9x4j6",
            max_capacity: 200,
            erlang_node_name: "admin@admin-k7m3n2p9x4j6.admin-cluster-1.nm.internal"
          },
          %{
            name: "admin-x9j4p2k7m8n3",
            max_capacity: 300,
            erlang_node_name: "admin@admin-x9j4p2k7m8n3.admin-cluster-1.nm.internal"
          }
        ]
      }
    })
  end

  defmodule EdgeClustersResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Edge Clusters Response",
      description: "All edge cluster assignments across all admins",
      type: :object,
      additionalProperties: %Schema{
        type: :object,
        description: "Clusters managed by this admin",
        additionalProperties: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "List of node IDs in this cluster"
        }
      },
      example: %{
        "admin-k7m3n2p9x4j6" => %{
          "cluster-x7j2p9k4m8n3" => ["node-uuid-1", "node-uuid-2"],
          "cluster-p4k7n2m9x3j6" => ["node-uuid-x"]
        },
        "admin-x9j4p2k7m8n3" => %{
          "cluster-j6m8n3p7k2x4" => [],
          "cluster-m3n9p2k8x7j4" => ["node-uuid-3"]
        }
      }
    })
  end
end
