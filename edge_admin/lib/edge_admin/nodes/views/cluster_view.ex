# edge_admin/lib/edge_admin/nodes/views/cluster_view.ex
defmodule EdgeAdmin.Nodes.Views.ClusterView do
  @moduledoc """
  Public-facing render for `Cluster` — the canonical map shape both REST
  and MCP serialize. Includes a nested `nodes` array with each node's
  identity + VPN hostname when the association is preloaded.
  """

  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.View
  alias EdgeAdmin.Vpn

  @spec render(Cluster.t()) :: map()
  def render(%Cluster{nodes: nodes} = cluster) do
    %{
      id: cluster.id,
      name: cluster.name,
      ipv4_range: cluster.ipv4_range,
      ipv6_range: cluster.ipv6_range,
      node_limit: cluster.node_limit,
      node_count: Cluster.node_count(cluster),
      nodes: View.render_embedded(nodes, &render_embedded_node(&1, cluster)),
      network_name: Cluster.network_name(cluster),
      vpn_domain: Cluster.vpn_domain(cluster),
      inserted_at: cluster.inserted_at,
      updated_at: cluster.updated_at
    }
  end

  defp render_embedded_node(node, cluster) do
    short_name = Node.node_name(node)
    network_name = Cluster.network_name(cluster)

    %{
      id: node.id,
      enrollment_key_id: node.enrollment_key_id,
      ingress_public_key: node.ingress_public_key,
      status: atom_to_string(node.status),
      vpn_hostname: Vpn.build_vpn_hostname(short_name, network_name)
    }
  end

  defp atom_to_string(value), do: Atom.to_string(value)
end
