# edge_admin/lib/edge_admin/nodes/views/node_view.ex
defmodule EdgeAdmin.Nodes.Views.NodeView do
  @moduledoc """
  Public-facing render for `Node` — the canonical map shape both REST and
  MCP serialize. Includes computed hostnames + nested aliases with their
  per-alias `vpn_hostname` when aliases are preloaded. Requires `cluster`
  to be preloaded.
  """

  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Node, as: NodeSchema

  @spec render(NodeSchema.t()) :: map()
  def render(%NodeSchema{cluster: cluster, aliases: aliases} = node) do
    %{
      id: node.id,
      node_name: NodeSchema.node_name(node),
      cluster_name: cluster.name,
      netmaker_host_id: node.netmaker_host_id,
      id_type: atom_to_string(node.id_type),
      status: atom_to_string(node.status),
      vpn_hostname: NodeSchema.vpn_hostname(node),
      mdns_hostname: NodeSchema.mdns_hostname(node),
      http_port: node.http_port,
      ssh_port: node.ssh_port,
      host_metrics_port: node.host_metrics_port,
      wireguard_metrics_port: node.wireguard_metrics_port,
      http_proxy_port: node.http_proxy_port,
      socks5_proxy_port: node.socks5_proxy_port,
      version: node.version,
      self_update_enabled: node.self_update_enabled,
      last_seen_at: node.last_seen_at,
      aliases: render_aliases(aliases),
      inserted_at: node.inserted_at,
      updated_at: node.updated_at
    }
  end

  defp render_aliases(aliases) when is_list(aliases), do: Enum.map(aliases, &alias_summary/1)
  defp render_aliases(_not_loaded), do: []

  defp alias_summary(a) do
    %{
      id: a.id,
      name: a.name,
      vpn_hostname: Alias.vpn_hostname(a)
    }
  end

  defp atom_to_string(value), do: Atom.to_string(value)
end
