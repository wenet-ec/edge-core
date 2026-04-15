# edge_admin/lib/edge_admin_mcp/tools/nodes/delete_node.ex
defmodule EdgeAdminMcp.Tools.Nodes.DeleteNode do
  @moduledoc "Remove a node from the system and its VPN mesh. The agent must re-enroll to reconnect."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes

  schema do
    field :node_id, {:required, :string}
  end

  @impl true
  def execute(%{node_id: id}, frame) do
    with {:ok, node} <- Nodes.get_node(id),
         {:ok, _} <- Nodes.delete_node(node) do
      {:reply, Response.text(Response.tool(), "Node #{id} deleted"), frame}
    else
      {:error, :not_found} ->
        {:reply, Response.json(Response.tool(), tool_error(:not_found, "Node #{id} not found")), frame}

      {:error, reason} ->
        {:reply, Response.json(Response.tool(), tool_error(reason)), frame}
    end
  end
end
