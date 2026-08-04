# edge_admin/lib/edge_admin_mcp/tools/nodes/create_node_recovery_key.ex
defmodule EdgeAdminMcp.Tools.Nodes.CreateNodeRecoveryKey do
  @moduledoc "Create or replace a node's one-use recovery key."
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
