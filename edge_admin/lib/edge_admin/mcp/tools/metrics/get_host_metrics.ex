# edge_admin/lib/edge_admin/mcp/tools/metrics/get_host_metrics.ex
defmodule EdgeAdmin.MCP.Tools.Metrics.GetHostMetrics do
  @moduledoc "Get host-level metrics for a node from Node Exporter — CPU, memory, disk, uptime."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Metrics

  schema do
    field :node_id, :string, required: true
  end

  @impl true
  def execute(%{node_id: node_id}, frame) do
    case Metrics.get_host_metrics(node_id) do
      {:ok, metrics} ->
        {:reply, Response.json(Response.tool(), metrics), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Host metrics unavailable: #{inspect(reason)}"), frame}
    end
  end
end
