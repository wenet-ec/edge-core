# edge_admin/lib/edge_admin_mcp/tools/nodes/delete_node_recovery_key.ex
defmodule EdgeAdminMcp.Tools.Nodes.DeleteNodeRecoveryKey do
  @moduledoc "Delete a node's active recovery key."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes

  @impl true
  def title, do: "Delete Node Recovery Key"

  @impl true
  def annotations, do: %{"destructiveHint" => true, "idempotentHint" => true, "openWorldHint" => true}

  schema do
    field :node_id, {:required, :string}
  end

  @impl true
  def execute(%{node_id: id}, frame) do
    with {:ok, node} <- Nodes.get_node(id),
         {:ok, _node} <- Nodes.delete_node_recovery_key(node) do
      {:reply, Response.json(Response.tool(), %{deleted: true, node_id: id}), frame}
    else
      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Node #{id} not found"), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
