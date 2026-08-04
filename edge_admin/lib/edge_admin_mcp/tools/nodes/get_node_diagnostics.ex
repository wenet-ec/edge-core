# edge_admin/lib/edge_admin_mcp/tools/nodes/get_node_diagnostics.ex
defmodule EdgeAdminMcp.Tools.Nodes.GetNodeDiagnostics do
  @moduledoc """
  Get the latest diagnostic report submitted by an edge node.

  - `node_id` — required. The node whose diagnostic report should be fetched.

  This is a read-only operation. It returns the latest stored report and does
  not trigger a new diagnostic collection on the Agent.
  """

  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Views.NodeDiagnosticView

  @impl true
  def title, do: "Get Node Diagnostics"

  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => true}

  schema do
    field :node_id, {:required, :string}
  end

  @impl true
  def execute(%{node_id: node_id}, frame) do
    case Nodes.get_node_diagnostics(node_id) do
      {:ok, diagnostic} ->
        {:reply, Response.json(Response.tool(), NodeDiagnosticView.render(diagnostic)), frame}

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Node #{node_id} not found"), frame}

      {:error, _reason} ->
        {:reply, error_response(:service_unavailable), frame}
    end
  end
end
