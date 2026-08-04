# edge_admin/lib/edge_admin/nodes/views/node_diagnostic_view.ex
defmodule EdgeAdmin.Nodes.Views.NodeDiagnosticView do
  @moduledoc """
  Canonical node-diagnostic render shared by REST and MCP.
  """

  alias EdgeAdmin.Nodes.Schemas.NodeDiagnostic

  @spec render(map()) :: %{collected_at: String.t(), overall: String.t(), checks: [map()]}
  def render(%{"collected_at" => collected_at, "overall" => overall, "checks" => checks}) do
    %{
      collected_at: collected_at,
      overall: overall,
      checks: checks
    }
  end

  @spec render_push(NodeDiagnostic.t()) :: map()
  def render_push(%NodeDiagnostic{} = diagnostic) do
    %{
      id: diagnostic.id,
      node_id: diagnostic.node_id,
      updated_at: diagnostic.updated_at
    }
  end
end
