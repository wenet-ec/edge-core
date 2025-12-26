# edge_admin/lib/edge_admin_web/controllers/nodes/node_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.NodeJSON do
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Node

  @doc """
  Renders a paginated list of nodes.
  """
  def index(%{nodes: nodes, meta: %Flop.Meta{} = meta}) do
    %{
      data: for(node <- nodes, do: data(node)),
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
  Renders a single node.
  """
  def show(%{node: node}) do
    %{data: data(node)}
  end

  defp data(%Node{cluster: cluster} = node) do
    # Check if aliases are preloaded
    aliases =
      case node.aliases do
        %Ecto.Association.NotLoaded{} -> []
        loaded_aliases -> Enum.map(loaded_aliases, &alias_data/1)
      end

    %{
      id: node.id,
      node_name: Node.node_name(node),
      cluster_name: cluster.name,
      netmaker_host_id: node.netmaker_host_id,
      id_type: node.id_type,
      status: node.status,
      dns_hostname: Node.dns_hostname(node),
      http_port: node.http_port,
      ssh_port: node.ssh_port,
      host_metrics_port: node.host_metrics_port,
      http_proxy_port: node.http_proxy_port,
      socks5_proxy_port: node.socks5_proxy_port,
      api_token: node.api_token,
      proxy_password: node.proxy_password,
      version: node.version,
      self_update_enabled: node.self_update_enabled,
      last_seen_at: node.last_seen_at,
      aliases: aliases,
      inserted_at: node.inserted_at,
      updated_at: node.updated_at
    }
  end

  defp alias_data(%Alias{} = alias_record) do
    %{
      id: alias_record.id,
      name: alias_record.name,
      dns_hostname: Alias.dns_hostname(alias_record)
    }
  end
end
