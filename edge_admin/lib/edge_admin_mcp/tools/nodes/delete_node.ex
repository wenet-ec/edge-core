# edge_admin/lib/edge_admin_mcp/tools/nodes/delete_node.ex
defmodule EdgeAdminMcp.Tools.Nodes.DeleteNode do
  @moduledoc """
  Delete an edge node from the Admin system.

  - `node_id` — required. The node to remove.

  This removes the node's Admin record and its node-owned resources. The
  running Agent is not stopped; it must register again before it can reconnect
  to this Admin. Treat this as a destructive operation.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes

  @impl true
  def title, do: "Delete Node"
  @impl true
  def annotations, do: %{"destructiveHint" => true, "idempotentHint" => false, "openWorldHint" => true}

  schema do
    field :node_id, {:required, :string}
  end

  @impl true
  def execute(%{node_id: id}, frame) do
    with {:ok, node} <- Nodes.get_node(id),
         {:ok, _} <- Nodes.delete_node(node) do
      {:reply, Response.json(Response.tool(), %{deleted: true, id: id}), frame}
    else
      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Node #{id} not found"), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
