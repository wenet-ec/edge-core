# edge_admin/lib/edge_admin/mcp/tools/nodes/node_data.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.NodeData do
  @moduledoc false

  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Node

  def data(%Node{cluster: cluster, aliases: aliases} = node) do
    %{
      id: node.id,
      node_name: Node.node_name(node),
      cluster_name: cluster.name,
      netmaker_host_id: node.netmaker_host_id,
      id_type: node.id_type,
      status: node.status,
      vpn_hostname: Node.vpn_hostname(node),
      mdns_hostname: Node.mdns_hostname(node),
      lan_hostname: Node.lan_hostname(node),
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
      aliases: Enum.map(aliases, fn a -> %{id: a.id, name: a.name, vpn_hostname: Alias.vpn_hostname(a)} end),
      inserted_at: node.inserted_at,
      updated_at: node.updated_at
    }
  end
end
