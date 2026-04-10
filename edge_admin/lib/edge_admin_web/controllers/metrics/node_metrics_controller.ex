# edge_admin/lib/edge_admin_web/controllers/metrics/node_metrics_controller.ex
defmodule EdgeAdminWeb.Controllers.Metrics.NodeMetricsController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Metrics
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Metrics.NodeMetricsSchemas

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true
  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:show_unified, :show_host, :show_agent]

  tags(["Nodes.Metrics"])

  operation(:show_unified,
    summary: "Get unified metrics for a node",
    description: """
    Returns aggregated metrics from all available sources for a node:
    - Host metrics (Node Exporter): CPU, memory, disk, uptime
    - Agent metrics (agent PromEx): BEAM stats, commands, proxy, SSH, VPN, health check, Oban

    Provides a complete view of node health and performance in a single request.
    Uses best-effort fetching - if one source fails, others are still returned.
    """,
    parameters: [
      node_id: [
        in: :path,
        description: "Node UUID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Unified metrics retrieved successfully", "application/json", NodeMetricsSchemas.UnifiedMetricsResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"Metrics unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  @doc """
  Returns unified metrics from all sources (host, agent, etc.).

  Fetches metrics in parallel from all available sources and aggregates them.
  Uses best-effort approach - partial failures don't fail the entire request.
  """
  def show_unified(conn, %{node_id: node_id}) do
    {:ok, unified_metrics} = Metrics.get_unified_metrics(node_id)
    render(conn, :show_unified, metrics: unified_metrics)
  end

  operation(:show_host,
    summary: "Get host metrics for a node",
    description: """
    Returns host-level system metrics from Node Exporter:
    - CPU: cores, load averages
    - Memory: usage, total/available/used in bytes and GB
    - Disk: usage, total/available/used for root filesystem
    - Uptime: seconds and human-readable format
    """,
    parameters: [
      node_id: [
        in: :path,
        description: "Node UUID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Host metrics retrieved successfully", "application/json", NodeMetricsSchemas.HostMetricsResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"Metrics unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  @doc """
  Returns host-level metrics only (Node Exporter).
  """
  def show_host(conn, %{node_id: node_id}) do
    with {:ok, metrics} <- Metrics.get_host_metrics(node_id) do
      render(conn, :show_host, metrics: metrics)
    end
  end

  operation(:show_agent,
    summary: "Get agent metrics for a node",
    description: """
    Returns application-level metrics from the edge_agent PromEx:
    - Application: uptime, BEAM stats (processes, memory breakdown)
    - Commands: sync/enqueue/complete/report statistics
    - Discovery: admin discovery scan metrics
    - Proxy: HTTP and SOCKS5 connection and blocked-request statistics
    - SSH: authentication attempts and connection count
    - VPN: config pull count (daily backstop for DNS recovery)
    - Health Check: fallback health report count (only non-zero when VPN is down)
    - Oban: job queue states (available, executing, completed, etc.)
    """,
    parameters: [
      node_id: [
        in: :path,
        description: "Node UUID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Agent metrics retrieved successfully", "application/json", NodeMetricsSchemas.AgentMetricsResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      503 => {"Metrics unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  @doc """
  Returns agent application metrics (PromEx).
  """
  def show_agent(conn, %{node_id: node_id}) do
    with {:ok, metrics} <- Metrics.get_agent_metrics(node_id) do
      render(conn, :show_agent, metrics: metrics)
    end
  end
end
