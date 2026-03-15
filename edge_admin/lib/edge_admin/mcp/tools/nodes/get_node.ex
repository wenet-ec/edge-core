# edge_admin/lib/edge_admin/mcp/tools/nodes/get_node.ex
defmodule EdgeAdmin.MCP.Tools.Nodes.GetNode do
  @moduledoc "Get a node by ID."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Schemas.Node

  schema do
    field :node_id, :string, required: true
  end

  @impl true
  def execute(%{node_id: id}, frame) do
    case Nodes.get_node(id) do
      {:ok, n} ->
        {:reply,
         Response.json(Response.tool(), %{
           id: n.id,
           name: Node.node_name(n),
           cluster: n.cluster.name,
           status: n.status,
           last_seen_at: n.last_seen_at,
           http_port: n.http_port,
           ssh_port: n.ssh_port,
           http_proxy_port: n.http_proxy_port,
           socks5_proxy_port: n.socks5_proxy_port,
           netmaker_host_id: n.netmaker_host_id,
           mdns_hostname: Node.mdns_hostname(n),
           lan_hostname: Node.lan_hostname(n),
           version: n.version,
           inserted_at: n.inserted_at
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Node #{id} not found"), frame}
    end
  end
end
