# edge_admin/lib/edge_admin_web/controllers/nodes/alias_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.AliasJSON do
  alias EdgeAdmin.FilteringPagination
  alias EdgeAdmin.Nodes.Alias

  @doc """
  Renders a paginated list of aliases.
  """
  def index(%{page_result: %FilteringPagination{} = page_result}) do
    %{
      data: for(alias_record <- page_result.data, do: data(alias_record)),
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
  Renders a single alias.
  """
  def show(%{alias: alias_record}) do
    %{data: data(alias_record)}
  end

  defp data(%Alias{cluster: cluster} = alias_record) do
    %{
      id: alias_record.id,
      name: alias_record.name,
      dns_hostname: Alias.dns_hostname(alias_record),
      node_id: alias_record.node_id,
      cluster_name: cluster.name,
      inserted_at: alias_record.inserted_at,
      updated_at: alias_record.updated_at
    }
  end
end
