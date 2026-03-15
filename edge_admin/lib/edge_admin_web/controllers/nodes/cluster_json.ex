# edge_admin_web/lib/edge_admin_web/controllers/nodes/cluster_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.ClusterJSON do
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Vpn

  @doc """
  Renders a paginated list of clusters.
  """
  def index(%{clusters: clusters, meta: %Flop.Meta{} = meta}) do
    %{
      data: for(cluster <- clusters, do: data(cluster)),
      pagination: %{
        page: meta.current_page,
        page_size: meta.page_size,
        total: meta.total_count,
        total_pages: meta.total_pages,
        has_next: meta.has_next_page?,
        has_prev: meta.has_previous_page?
      }
    }
  end

  @doc """
  Renders a single cluster.
  """
  def show(%{cluster: cluster}) do
    %{data: data(cluster)}
  end

  defp data(%Cluster{nodes: nodes} = cluster) do
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
    # Build DNS hostname using cluster we already have (avoid circular preload)
    short_name = Vpn.build_vpn_name(node.id, prefix: :node)
    network_name = Vpn.build_network_name(cluster.name, prefix: :node)
    vpn_hostname = Vpn.build_vpn_hostname(short_name, network_name)

    %{
      id: node.id,
      status: node.status,
      id_type: node.id_type,
      vpn_hostname: vpn_hostname
    }
  end
end
