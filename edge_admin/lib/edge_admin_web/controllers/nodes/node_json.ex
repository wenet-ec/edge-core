# edge_admin/lib/edge_admin_web/controllers/nodes/node_json.ex
defmodule EdgeAdminWeb.Nodes.NodeJSON do
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

  def index(%{nodes: nodes}) do
    %{data: for(node <- nodes, do: data(node))}
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
      id_type: node.id_type,
      vpn_ip: node.vpn_ip,
      vpn_hostname: node.vpn_hostname,
      last_seen_at: node.last_seen_at,
      status: node.status,
      inserted_at: node.inserted_at,
      updated_at: node.updated_at
    }
  end
end
