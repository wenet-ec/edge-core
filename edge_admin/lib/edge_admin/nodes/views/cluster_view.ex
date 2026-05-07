# edge_admin/lib/edge_admin/nodes/views/cluster_view.ex
defmodule EdgeAdmin.Nodes.Views.ClusterView do
  @moduledoc """
  Public-facing render for `Cluster` — the canonical map shape both REST
  and MCP serialize. Includes a nested `nodes` array with each node's
  identity + VPN hostname. Requires `nodes` to be preloaded.
  """

  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Vpn

  @spec render(Cluster.t()) :: map()
  def render(%Cluster{nodes: nodes} = cluster) do
    %{
      id: cluster.id,
      name: cluster.name,
      ipv4_range: cluster.ipv4_range,
      node_limit: cluster.node_limit,
      node_count: Cluster.node_count(cluster),
      nodes: Enum.map(nodes, &node_summary(&1, cluster)),
      network_name: Cluster.network_name(cluster),
      vpn_domain: Cluster.vpn_domain(cluster),
      inserted_at: cluster.inserted_at,
      updated_at: cluster.updated_at
    }
  end

  defp node_summary(node, cluster) do
    short_name = Vpn.build_vpn_name(node.id, prefix: :node)
    network_name = Vpn.build_network_name(cluster.name, prefix: :node)

    %{
      id: node.id,
      status: node.status,
      id_type: node.id_type,
      vpn_hostname: Vpn.build_vpn_hostname(short_name, network_name)
    }
  end
end
