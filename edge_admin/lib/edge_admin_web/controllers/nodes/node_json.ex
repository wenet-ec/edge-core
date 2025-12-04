# edge_admin/lib/edge_admin_web/controllers/nodes/node_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.NodeJSON do
  alias EdgeAdmin.FilteringPagination
  alias EdgeAdmin.Nodes.Node

  @doc """
  Renders a paginated list of nodes.
  """
  def index(%{page_result: %FilteringPagination{} = page_result}) do
    %{
      data: for(node <- page_result.data, do: data(node)),
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
  Renders a single node.
  """
  def show(%{node: node}) do
    %{data: data(node)}
  end

  defp data(%Node{} = node) do
    %{
      id: node.id,
      node_name: Node.node_name(node),
      cluster_id: node.cluster_id,
      netmaker_host_id: node.netmaker_host_id,
      id_type: node.id_type,
      status: node.status,
      dns_hostname: Node.dns_hostname(node),
      http_url: Node.http_url(node),
      http_port: node.http_port,
      ssh_port: node.ssh_port,
      metrics_port: node.metrics_port,
      http_proxy_port: node.http_proxy_port,
      socks5_proxy_port: node.socks5_proxy_port,
      version: node.version,
      self_update_enabled: node.self_update_enabled,
      last_seen_at: node.last_seen_at,
      inserted_at: node.inserted_at,
      updated_at: node.updated_at
    }
  end
end
