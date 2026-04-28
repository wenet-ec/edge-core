# edge_admin/lib/edge_admin_web/schemas/admins/admin_schemas.ex
defmodule EdgeAdminWeb.Schemas.Admins.AdminSchemas do
  @moduledoc """
  OpenAPI schemas for admin metadata endpoints.
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
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

    schema(CommonSchemas.single_response(Admin, "AdminResponse", "Single admin identity response"))
  end

  defmodule AdminTopologyEntry do
    @moduledoc false

    schema(%{
      title: "AdminTopologyEntry",
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

  defmodule MyAdminCluster do
    @moduledoc false

    schema(%{
      title: "MyAdminCluster",
      description: "Topology and state of the admin cluster this admin belongs to.",
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
        weak_leader: %Schema{
          type: :string,
          description:
            "Name of the current weak leader admin (alphabetically first admin ID in the cluster). Best-effort duplicate work reduction — not a strong guarantee. Always populated — defaults to self on bootstrap, updated on first metadata recomputation."
        },
        topology: %Schema{
          type: :array,
          items: AdminTopologyEntry,
          description: "List of all admins in the cluster"
        }
      },
      required: [:name, :total_admins, :total_nodes, :total_capacity, :degraded, :weak_leader, :topology],
      example: %{
        name: "admin-cluster-1",
        total_admins: 2,
        total_nodes: 42,
        total_capacity: 500,
        degraded: false,
        weak_leader: "admin-k7m3n2p9x4j6",
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

  defmodule MyAdminClusterResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(
        MyAdminCluster,
        "MyAdminClusterResponse",
        "Topology and state of the admin cluster this admin belongs to"
      )
    )
  end

  defmodule EdgeClusters do
    @moduledoc false

    schema(%{
      title: "EdgeClusters",
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

    schema(
      CommonSchemas.single_response(
        EdgeClusters,
        "EdgeClustersResponse",
        "All edge cluster assignments across all admins"
      )
    )
  end

  defmodule OrphanedClusters do
    @moduledoc false

    schema(%{
      title: "OrphanedClusters",
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

    schema(
      CommonSchemas.single_response(
        OrphanedClusters,
        "OrphanedClustersResponse",
        "Clusters with no assigned admin instance"
      )
    )
  end

  defmodule AdminDiscoveryData do
    @moduledoc false

    schema(%{
      title: "Internal.AdminDiscoveryData",
      description: "Admin identity returned during agent VPN bootstrap discovery",
      type: :object,
      properties: %{
        name: %Schema{type: :string, description: "Admin name (e.g. admin-k7m3n2p9x4j6)"}
      },
      required: [:name],
      example: %{name: "admin-k7m3n2p9x4j6"}
    })
  end

  defmodule DiscoveryResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(
        AdminDiscoveryData,
        "Internal.AdminDiscoveryResponse",
        "Admin identity returned during agent VPN bootstrap discovery"
      )
    )
  end

  defmodule AdminClusterMember do
    @moduledoc false

    schema(%{
      title: "AdminClusterMember",
      description:
        "An admin instance present in a Netmaker admin-cluster network. May include stale/disconnected entries.",
      type: :object,
      properties: %{
        name: %Schema{type: :string, description: "Admin name (e.g., admin-k7m3n2p9x4j6)"},
        vpn_hostname: %Schema{type: :string, description: "DNS hostname inside the admin cluster network"},
        netmaker_host_id: %Schema{type: :string, description: "Netmaker host ID (UUID)"},
        ipv4_address: %Schema{
          type: :string,
          description: "IPv4 address assigned within the admin cluster CIDR (without prefix length)",
          nullable: true
        },
        wireguard_ip_address: %Schema{
          type: :string,
          description: "IP address WireGuard peers send tunnel packets to (public or LAN-reachable)",
          nullable: true
        },
        wireguard_port: %Schema{
          type: :integer,
          description: "WireGuard listen port",
          nullable: true
        },
        use_static_port: %Schema{
          type: :boolean,
          description: "True when the admin pins WireGuard to a fixed port across restarts"
        },
        status: %Schema{
          type: :string,
          enum: ["online", "offline", "disconnected"],
          description:
            "Netmaker-derived status: online (recent checkin), offline (stale checkin), disconnected (admin disabled)",
          nullable: true
        },
        last_checked_in: %Schema{
          type: :string,
          format: :"date-time",
          description: "Last time this admin's netclient reported in to Netmaker (ISO 8601)",
          nullable: true
        }
      },
      required: [:name, :vpn_hostname, :netmaker_host_id],
      example: %{
        name: "admin-7k3m9p2n",
        vpn_hostname: "admin-7k3m9p2n.admin-cluster-main.nm.internal",
        netmaker_host_id: "f272e703-b48f-4b61-b4c1-bfe4fffde62b",
        ipv4_address: "100.64.0.1",
        wireguard_ip_address: "10.0.0.7",
        wireguard_port: 51_820,
        use_static_port: true,
        status: "online",
        last_checked_in: "2026-04-28T12:34:56Z"
      }
    })
  end

  defmodule AdminCluster do
    @moduledoc false

    schema(%{
      title: "AdminCluster",
      description: "An admin cluster as known to Netmaker, plus its admin members.",
      type: :object,
      properties: %{
        name: %Schema{type: :string, description: "Admin cluster network name (e.g., admin-cluster-main)"},
        ipv4_range: %Schema{type: :string, description: "IPv4 CIDR for the admin cluster network"},
        admin_count: %Schema{type: :integer, description: "Number of admins in this cluster"},
        admins: %Schema{
          type: :array,
          items: AdminClusterMember,
          description: "Admins present in this cluster, sorted by name"
        }
      },
      required: [:name, :ipv4_range, :admin_count, :admins],
      example: %{
        name: "admin-cluster-main",
        ipv4_range: "100.64.0.0/24",
        admin_count: 1,
        admins: [
          %{
            name: "admin-7k3m9p2n",
            vpn_hostname: "admin-7k3m9p2n.admin-cluster-main.nm.internal",
            netmaker_host_id: "f272e703-b48f-4b61-b4c1-bfe4fffde62b",
            ipv4_address: "100.64.0.1",
            wireguard_ip_address: "10.0.0.7",
            wireguard_port: 51_820,
            use_static_port: true,
            status: "online",
            last_checked_in: "2026-04-28T12:34:56Z"
          }
        ]
      }
    })
  end

  defmodule AdminClusters do
    @moduledoc false

    schema(%{
      title: "AdminClusters",
      description: "All admin clusters Netmaker knows about, sorted by name.",
      type: :array,
      items: AdminCluster
    })
  end

  defmodule AdminClustersResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(
        AdminClusters,
        "AdminClustersResponse",
        "All admin clusters Netmaker knows about"
      )
    )
  end
end
