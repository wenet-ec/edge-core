# edge_admin/lib/edge_admin_mcp/tools/metrics/get_node_metrics.ex
defmodule EdgeAdminMcp.Tools.Metrics.GetNodeMetrics do
  @moduledoc """
  Get unified metrics for a node — host + agent sources combined.

  Returns CPU, memory, disk, uptime (from Node Exporter) plus BEAM stats,
  command pipeline, admin discovery, proxy, SSH, VPN pulls, health check
  reports, and Oban queues (from agent PromEx). Best-effort: if one
  source fails, the corresponding section is reported as unavailable but
  the call still succeeds.

  ## Note on bogus node IDs

  This tool always returns `{:ok, ...}` even if `node_id` doesn't exist —
  the per-source fetch errors get folded into "unavailable" status.
  Verify the node exists with `get_node` first if you need to
  distinguish "node missing" from "node up but not scraping". The
  per-source tools (`get_host_metrics`, `get_agent_metrics`) do return
  an explicit `not_found` error for missing nodes.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Metrics

  @impl true
  def title, do: "Get Node Metrics"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

  schema do
    field :node_id, {:required, :string}
  end

  @impl true
  def execute(%{node_id: node_id}, frame) do
    {:ok, metrics} = Metrics.get_unified_metrics(node_id)
    {:reply, Response.json(Response.tool(), metrics), frame}
  end
end
