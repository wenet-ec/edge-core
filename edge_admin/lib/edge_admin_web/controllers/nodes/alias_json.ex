# edge_admin/lib/edge_admin_web/controllers/nodes/alias_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.AliasJSON do
  alias EdgeAdmin.Nodes.Schemas.Alias

  @doc """
  Renders a paginated list of aliases.
  """
  def index(%{aliases: aliases, meta: %Flop.Meta{} = meta}) do
    %{
      data: for(alias_record <- aliases, do: data(alias_record)),
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
