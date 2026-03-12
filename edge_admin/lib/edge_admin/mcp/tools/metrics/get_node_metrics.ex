# edge_admin/lib/edge_admin/mcp/tools/metrics/get_node_metrics.ex
defmodule EdgeAdmin.MCP.Tools.Metrics.GetNodeMetrics do
  @moduledoc """
  Get unified metrics for a node — host + agent sources combined.

  Returns CPU, memory, disk, uptime (from Node Exporter) plus BEAM stats,
  command pipeline, proxy, SSH, and Oban queues (from agent PromEx).
  Best-effort: if one source fails, the others are still returned.
  """
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Metrics

  schema do
    field :node_id, :string, required: true
  end

  @impl true
  def execute(%{node_id: node_id}, frame) do
    {:ok, metrics} = Metrics.get_unified_metrics(node_id)
    {:reply, Response.json(Response.tool(), metrics), frame}
  end
end
