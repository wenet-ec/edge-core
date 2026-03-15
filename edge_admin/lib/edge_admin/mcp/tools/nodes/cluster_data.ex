# edge_admin/lib/edge_admin/mcp/tools/nodes/cluster_data.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.ClusterData do
  @moduledoc false

  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Vpn

  def data(%Cluster{nodes: nodes} = cluster) do
    %{
      id: cluster.id,
      name: cluster.name,
      ipv4_range: cluster.ipv4_range,
      node_limit: cluster.node_limit,
      node_count: Cluster.node_count(cluster),
      nodes: Enum.map(nodes, &node_data(&1, cluster)),
      network_name: Cluster.network_name(cluster),
      vpn_domain: Cluster.vpn_domain(cluster),
      inserted_at: cluster.inserted_at,
      updated_at: cluster.updated_at
    }
  end

  defp node_data(node, cluster) do
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
