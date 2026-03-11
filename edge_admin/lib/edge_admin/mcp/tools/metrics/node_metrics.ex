# edge_admin/lib/edge_admin/mcp/tools/metrics/node_metrics.ex
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

defmodule EdgeAdmin.MCP.Tools.Metrics.GetAgentMetrics do
  @moduledoc "Get agent application metrics for a node from edge_agent PromEx — BEAM stats, commands, proxy, SSH, Oban queues."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Metrics

  schema do
    field :node_id, :string, required: true
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
