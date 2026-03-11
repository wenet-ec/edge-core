# edge_admin/lib/edge_admin/mcp/tools/metrics/admin_metrics.ex
defmodule EdgeAdmin.MCP.Tools.Metrics.GetAdminMetrics do
  @moduledoc "Get metrics for this admin instance from edge_admin PromEx — BEAM stats, cluster metadata, Oban queues."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Metrics

  schema do
  end

  @impl true
  def execute(_params, frame) do
    case Metrics.get_admin_metrics() do
      {:ok, metrics} ->
        {:reply, Response.json(Response.tool(), metrics), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Admin metrics unavailable: #{inspect(reason)}"), frame}
    end
  end
end
