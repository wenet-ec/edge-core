# edge_admin/lib/edge_admin_mcp/tools/nodes/get_node.ex
defmodule EdgeAdminMcp.Tools.Nodes.GetNode do
  @moduledoc """
  Get an edge node by ID.

  - `node_id` — required. The node to retrieve.

  The response includes the node's cluster assignment, connection details,
  health state, aliases, and other non-secret registration fields.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Views.NodeView

  @impl true
  def title, do: "Get Node"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :node_id, {:required, :string}
  end

  @impl true
  def execute(%{node_id: id}, frame) do
    case Nodes.get_node(id) do
      {:ok, node} ->
        {:reply, Response.json(Response.tool(), NodeView.render(node)), frame}

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Node #{id} not found"), frame}
    end
  end
end
