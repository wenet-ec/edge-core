# edge_admin/lib/edge_admin_mcp/tools/metrics/get_agent_metrics.ex
defmodule EdgeAdminMcp.Tools.Metrics.GetAgentMetrics do
  @moduledoc "Get agent application metrics for a node from edge_agent PromEx — BEAM stats, commands, discovery, proxy, SSH, VPN pulls, health check reports, Oban queues."
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Metrics

  @impl true
  def title, do: "Get Agent Metrics"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => true}

  schema do
    field :node_id, {:required, :string}
  end

  @impl true
  def execute(%{node_id: node_id}, frame) do
    case Metrics.get_agent_metrics(node_id) do
      {:ok, metrics} ->
        {:reply, Response.json(Response.tool(), metrics), frame}

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Node #{node_id} not found"), frame}

      {:error, _reason} ->
        {:reply, error_response(:service_unavailable), frame}
    end
  end
end
