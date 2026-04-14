# edge_admin/lib/edge_admin_mcp/tools/metrics/get_agent_metrics.ex
defmodule EdgeAdminMcp.Tools.Metrics.GetAgentMetrics do
  @moduledoc "Get agent application metrics for a node from edge_agent PromEx — BEAM stats, commands, discovery, proxy, SSH, VPN pulls, health check reports, Oban queues."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Metrics

  schema do
    field :node_id, {:required, :string}
  end

  @impl true
  def execute(%{node_id: node_id}, frame) do
    case Metrics.get_agent_metrics(node_id) do
      {:ok, metrics} ->
        {:reply, Response.json(Response.tool(), metrics), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Agent metrics unavailable: #{inspect(reason)}"), frame}
    end
  end
end
