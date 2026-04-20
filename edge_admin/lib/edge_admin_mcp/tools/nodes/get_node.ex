# edge_admin/lib/edge_admin_mcp/tools/nodes/get_node.ex
defmodule EdgeAdminMcp.Tools.Nodes.GetNode do
  @moduledoc "Get a node by ID."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdminMcp.Tools.Nodes.NodeData

  @impl true
  def title, do: "Get Node"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

  schema do
    field :node_id, {:required, :string}
  end

  @impl true
  def execute(%{node_id: id}, frame) do
    case Nodes.get_node(id) do
      {:ok, node} ->
        {:reply, Response.json(Response.tool(), NodeData.data(node)), frame}

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Node #{id} not found"), frame}
    end
  end
end
