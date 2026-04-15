# edge_admin/lib/edge_admin_mcp/tools/metrics/get_host_metrics.ex
defmodule EdgeAdminMcp.Tools.Metrics.GetHostMetrics do
  @moduledoc "Get host-level metrics for a node from Node Exporter — CPU, memory, disk, uptime."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Metrics

  schema do
    field :node_id, {:required, :string}
  end

  @impl true
  def execute(%{node_id: node_id}, frame) do
    case Metrics.get_host_metrics(node_id) do
      {:ok, metrics} ->
        {:reply, Response.json(Response.tool(), metrics), frame}

      {:error, _reason} ->
        {:reply, Response.json(Response.tool(), tool_error(:service_unavailable)), frame}
    end
  end
end
