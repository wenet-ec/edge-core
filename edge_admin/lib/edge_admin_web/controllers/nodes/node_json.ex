# edge_admin/lib/edge_admin_web/controllers/nodes/node_json.ex
defmodule EdgeAdminWeb.Nodes.NodeJSON do
  alias EdgeAdmin.Nodes.Node

  @doc """
  Renders a list of nodes.
  """
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
      hardware_id: node.hardware_id,
      vpn_ip: node.vpn_ip,
      vpn_hostname: node.vpn_hostname,
      last_seen_at: node.last_seen_at,
      status: node.status
    }
  end
end
