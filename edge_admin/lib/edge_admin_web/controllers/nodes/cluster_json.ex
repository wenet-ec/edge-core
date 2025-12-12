# edge_admin_web/lib/edge_admin_web/controllers/nodes/cluster_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.ClusterJSON do
  alias EdgeAdmin.FilteringPagination
  alias EdgeAdmin.Nodes.Cluster

  @doc """
  Renders a paginated list of clusters.
  """
  def index(%{page_result: %FilteringPagination{} = page_result}) do
    %{
      data: for(cluster <- page_result.data, do: data(cluster)),
      pagination: %{
        page: page_result.page,
        page_size: page_result.page_size,
        total: page_result.total,
        total_pages: page_result.total_pages,
        has_next: page_result.has_next,
        has_prev: page_result.has_prev
      },
      filters: page_result.filters,
      sort: Enum.map(page_result.sort, fn {field, direction} -> "#{field}:#{direction}" end)
    }
  end

  @doc """
  Renders a single cluster.
  """
  def show(%{cluster: cluster}) do
    %{data: data(cluster)}
  end

  defp data(%Cluster{} = cluster) do
    %{
      id: cluster.id,
      name: cluster.name,
      ipv4_range: cluster.ipv4_range,
      node_count: Cluster.node_count(cluster),
      nodes: Enum.map(cluster.nodes, &node_summary/1),
      network_name: Cluster.network_name(cluster),
      dns_domain: Cluster.dns_domain(cluster),
      inserted_at: cluster.inserted_at,
      updated_at: cluster.updated_at
    }
  end

  defp node_summary(node) do
    %{
      id: node.id,
      status: node.status,
      id_type: node.id_type,
      dns_hostname: EdgeAdmin.Nodes.Node.dns_hostname(node)
    }
  end
end
