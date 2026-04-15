# edge_admin/lib/edge_admin_web/controllers/nodes/node_json.ex
defmodule EdgeAdminWeb.Controllers.Nodes.NodeJSON do
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, nodes: nodes, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(nodes, &data/1), flop_meta)
  end

  def show(%{conn: conn, node: node}) do
    ResponseEnvelope.success(conn, data(node))
  end

  defp data(%Node{cluster: cluster, aliases: aliases} = node) do
    %{
      id: node.id,
      node_name: Node.node_name(node),
      cluster_name: cluster.name,
      netmaker_host_id: node.netmaker_host_id,
      id_type: node.id_type,
      status: node.status,
      vpn_hostname: Node.vpn_hostname(node),
      mdns_hostname: Node.mdns_hostname(node),
      http_port: node.http_port,
      ssh_port: node.ssh_port,
      host_metrics_port: node.host_metrics_port,
      wireguard_metrics_port: node.wireguard_metrics_port,
      http_proxy_port: node.http_proxy_port,
      socks5_proxy_port: node.socks5_proxy_port,
      api_token: node.api_token,
      proxy_password: node.proxy_password,
      version: node.version,
      self_update_enabled: node.self_update_enabled,
      last_seen_at: node.last_seen_at,
      aliases: Enum.map(aliases, &alias_data/1),
      inserted_at: node.inserted_at,
      updated_at: node.updated_at
    }
  end

  defp alias_data(%Alias{} = alias_record) do
    %{
      id: alias_record.id,
      name: alias_record.name,
      vpn_hostname: Alias.vpn_hostname(alias_record)
    }
  end
end
