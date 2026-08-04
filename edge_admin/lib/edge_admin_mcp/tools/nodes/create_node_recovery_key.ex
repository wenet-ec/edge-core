# edge_admin/lib/edge_admin_mcp/tools/nodes/create_node_recovery_key.ex
defmodule EdgeAdminMcp.Tools.Nodes.CreateNodeRecoveryKey do
  @moduledoc """
  Create or replace a node's one-use recovery key.

  - `node_id` — required. The node for which recovery is being provisioned.

  The returned key is a sensitive recovery credential and is only available in
  this creation response; it is not included in normal node reads or lists.
  Creating a new key invalidates the previous key. The key is bound to the
  node's current cluster and is consumed when the Agent successfully recovers
  that node after losing its local installation data. Moving the node to a
  different cluster clears the key; create a new one explicitly if recovery is
  needed in the new cluster.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes

  @impl true
  def title, do: "Create Node Recovery Key"

  @impl true
  def annotations, do: %{"destructiveHint" => true, "idempotentHint" => false, "openWorldHint" => true}

  schema do
    field :node_id, {:required, :string}
  end

  @impl true
  def execute(%{node_id: id}, frame) do
    with {:ok, node} <- Nodes.get_node(id),
         {:ok, recovery_key} <- Nodes.create_node_recovery_key(node) do
      {:reply, Response.json(Response.tool(), %{recovery_key: recovery_key}), frame}
    else
      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Node #{id} not found"), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
