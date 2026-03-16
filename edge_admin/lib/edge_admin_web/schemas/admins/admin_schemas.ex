# edge_admin/lib/edge_admin_web/schemas/admins/admin_schemas.ex
defmodule EdgeAdminWeb.Schemas.Admins.AdminSchemas do
  @moduledoc """
  OpenAPI schemas for admin metadata endpoints.
  """

  use EdgeAdminWeb.Schema

  alias OpenApiSpex.Schema

  defmodule Admin do
    @moduledoc false

    schema(%{
      title: "Admin",
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
        vpn_hostname: %Schema{
          type: :string,
          description: "DNS hostname for this admin"
        },
        admin_cluster_name: %Schema{
          type: :string,
          description: "Name of the admin cluster this admin belongs to"
        },
        netmaker_host_id: %Schema{
          type: :string,
          description: "Netmaker host ID for this admin (UUID format)"
        },
        last_computed_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "Last time metadata was computed",
          nullable: true
        }
      },
      required: [:id, :name, :max_capacity, :erlang_node_name, :vpn_hostname, :admin_cluster_name, :netmaker_host_id],
      example: %{
        id: "k7m3n2p9x4j6",
        name: "admin-k7m3n2p9x4j6",
        max_capacity: 200,
        erlang_node_name: "admin@admin-k7m3n2p9x4j6.admin-cluster-1.nm.internal",
        vpn_hostname: "admin-k7m3n2p9x4j6.admin-cluster-1.nm.internal",
        admin_cluster_name: "admin-cluster-1",
        netmaker_host_id: "95e2707e-d11f-4551-bdd4-4ab2ab917505",
        last_computed_at: "2025-01-15T12:00:00Z"
      }
    })
  end

  defmodule AdminResponse do
    @moduledoc false

    schema(%{
      title: "Admin Response",
      description: "Single admin identity response",
      type: :object,
      properties: %{
        data: Admin
      },
      required: [:data],
      example: %{
        data: %{
          id: "k7m3n2p9x4j6",
          name: "admin-k7m3n2p9x4j6",
          max_capacity: 200,
          erlang_node_name: "admin@admin-k7m3n2p9x4j6.admin-cluster-1.nm.internal",
          vpn_hostname: "admin-k7m3n2p9x4j6.admin-cluster-1.nm.internal",
          admin_cluster_name: "admin-cluster-1",
          netmaker_host_id: "95e2707e-d11f-4551-bdd4-4ab2ab917505",
          last_computed_at: "2025-01-15T12:00:00Z"
        }
      }
    })
  end

  defmodule AdminTopologyEntry do
    @moduledoc false

    schema(%{
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
        vpn_hostname: %Schema{
          type: :string,
          description: "Netmaker dns hostname"
        },
        erlang_node_name: %Schema{
          type: :string,
          description: "Erlang distribution node name"
        },
        netmaker_host_id: %Schema{
          type: :string,
          description: "Netmaker host ID for this admin (UUID format)"
        }
      },
      required: [:name, :max_capacity, :erlang_node_name, :netmaker_host_id],
      example: %{
        name: "admin-k7m3n2p9x4j6",
        max_capacity: 200,
        vpn_hostname: "admin-k7m3n2p9x4j6.admin-cluster-1.nm.internal",
        erlang_node_name: "admin@admin-k7m3n2p9x4j6.admin-cluster-1.nm.internal",
        netmaker_host_id: "95e2707e-d11f-4551-bdd4-4ab2ab917505"
      }
    })
  end

  defmodule AdminCluster do
    @moduledoc false

    schema(%{
      title: "Admin Cluster",
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
        total_nodes: %Schema{
          type: :integer,
          description: "Total nodes registered in the system across all clusters"
        },
        total_capacity: %Schema{
          type: :integer,
          description: "Sum of max_capacity across all admins in this admin cluster"
        },
        degraded: %Schema{
          type: :boolean,
          description: "True when total_nodes exceeds total_capacity"
        },
        topology: %Schema{
          type: :array,
          items: AdminTopologyEntry,
          description: "List of all admins in the cluster"
        }
      },
      required: [:name, :total_admins, :total_nodes, :total_capacity, :degraded, :topology],
      example: %{
        name: "admin-cluster-1",
        total_admins: 2,
        total_nodes: 42,
        total_capacity: 500,
        degraded: false,
        topology: [
          %{
            name: "admin-k7m3n2p9x4j6",
            max_capacity: 200,
            vpn_hostname: "admin-k7m3n2p9x4j6.admin-cluster-1.nm.internal",
            erlang_node_name: "admin@admin-k7m3n2p9x4j6.admin-cluster-1.nm.internal",
            netmaker_host_id: "95e2707e-d11f-4551-bdd4-4ab2ab917505"
          },
          %{
            name: "admin-x9j4p2k7m8n3",
            max_capacity: 300,
            vpn_hostname: "admin-x9j4p2k7m8n3.admin-cluster-1.nm.internal",
            erlang_node_name: "admin@admin-x9j4p2k7m8n3.admin-cluster-1.nm.internal",
            netmaker_host_id: "7f3c8d4e-9a1b-4c2d-8e3f-5a6b7c8d9e0f"
          }
        ]
      }
    })
  end

  defmodule AdminClusterResponse do
    @moduledoc false

    schema(%{
      title: "Admin Cluster Response",
      description: "Single admin cluster topology response",
      type: :object,
      properties: %{
        data: AdminCluster
      },
      required: [:data],
      example: %{
        data: %{
          name: "admin-cluster-1",
          total_admins: 2,
          total_nodes: 42,
          total_capacity: 500,
          degraded: false,
          topology: [
            %{
              name: "admin-k7m3n2p9x4j6",
              max_capacity: 200,
              vpn_hostname: "admin-k7m3n2p9x4j6.admin-cluster-1.nm.internal",
              erlang_node_name: "admin@admin-k7m3n2p9x4j6.admin-cluster-1.nm.internal",
              netmaker_host_id: "95e2707e-d11f-4551-bdd4-4ab2ab917505"
            }
          ]
        }
      }
    })
  end

  defmodule EdgeClusters do
    @moduledoc false

    schema(%{
      title: "Edge Clusters",
      description: "All edge cluster assignments across all admins",
      type: :object,
      additionalProperties: %Schema{
        type: :object,
        description: "Clusters managed by this admin",
        additionalProperties: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "List of node names in this cluster"
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

  defmodule EdgeClustersResponse do
    @moduledoc false

    schema(%{
      title: "Edge Clusters Response",
      description: "All edge cluster assignments across all admins",
      type: :object,
      properties: %{
        data: EdgeClusters
      },
      required: [:data],
      example: %{
        data: %{
          "admin-k7m3n2p9x4j6" => %{
            "cluster-x7j2p9k4m8n3" => ["node-uuid-1", "node-uuid-2"],
            "cluster-p4k7n2m9x3j6" => ["node-uuid-x"]
          },
          "admin-x9j4p2k7m8n3" => %{
            "cluster-j6m8n3p7k2x4" => [],
            "cluster-m3n9p2k8x7j4" => ["node-uuid-3"]
          }
        }
      }
    })
  end

  defmodule OrphanedClusters do
    @moduledoc false

    schema(%{
      title: "Orphaned Clusters",
      description:
        "Clusters that could not be assigned to any admin due to capacity constraints. Empty map when system is not degraded.",
      type: :object,
      additionalProperties: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "List of node names in this orphaned cluster"
      },
      example: %{
        "cluster-orphaned-1" => ["node-uuid-5", "node-uuid-6"],
        "cluster-orphaned-2" => ["node-uuid-7"]
      }
    })
  end

  defmodule OrphanedClustersResponse do
    @moduledoc false

    schema(%{
      title: "Orphaned Clusters Response",
      description: "Clusters with no assigned admin instance",
      type: :object,
      properties: %{
        data: OrphanedClusters
      },
      required: [:data],
      example: %{
        data: %{
          "cluster-orphaned-1" => ["node-uuid-5", "node-uuid-6"],
          "cluster-orphaned-2" => ["node-uuid-7"]
        }
      }
    })
  end
end
