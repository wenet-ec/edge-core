# edge_admin/lib/edge_admin_web/controllers/metrics/admin_metrics_controller.ex
defmodule EdgeAdminWeb.Controllers.Metrics.AdminMetricsController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Metrics
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Metrics.AdminMetricsSchemas

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EdgeAdminWeb.Plugs.CastAndValidateErrorRenderer
  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:show_self]

  tags(["Admins.Metrics"])

  operation(:show_self,
    summary: "Get admin metrics for self",
    description: """
    Returns application-level metrics from the edge_admin PromEx:
    - Application: uptime, BEAM stats (processes, memory, atoms, ETS tables)
    - Metadata: degraded status, orphaned/assigned clusters
    - Bootstrap: step counts and full sequence completions
    - Discovery: peer discovery scan, DNS resolution, and connection counts
    - Nodes: health check statistics
    - Commands: delivery runs, per-execution delivery, completions, expirations
    - SSH: credential verification attempts and failures
    - Reconciliation: cluster Netmaker↔DB sync runs and errors
    - Self-updates: request processing completions
    - Gateways: connection events, active count, scrape totals
    - Event broker: publish/enqueue counters (zeroed when broker is disabled)
    - Oban: job queue states (available, scheduled, executing, etc.)
    """,
    parameters: [],
    responses: %{
      200 => {"Admin metrics retrieved successfully", "application/json", AdminMetricsSchemas.AdminMetricsResponse},
      503 => {"Metrics unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  @doc """
  Returns admin application metrics (PromEx).
  """
  def show_self(conn, _params) do
    with {:ok, metrics} <- Metrics.get_admin_metrics() do
      render(conn, :show_self, conn: conn, metrics: metrics)
    end
  end
end
