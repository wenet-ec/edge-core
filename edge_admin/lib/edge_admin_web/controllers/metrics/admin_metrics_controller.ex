# edge_admin/lib/edge_admin_web/controllers/metrics/admin_metrics_controller.ex
defmodule EdgeAdminWeb.Controllers.Metrics.AdminMetricsController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Metrics.AdminMetrics
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Metrics.AdminMetricsSchemas

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  tags(["Metrics.Admins"])

  operation(:show_self,
    summary: "Get admin metrics for self",
    description: """
    Returns application-level metrics from the edge_admin PromEx:
    - Application: uptime, BEAM stats (processes, memory, atoms, ETS tables)
    - Metadata: degraded status, orphaned/assigned clusters
    - Bootstrap: initialization step counts
    - Nodes: health check statistics
    - Oban: job queue states (available, scheduled, executing, etc.)
    """,
    parameters: [],
    responses: %{
      200 => {"Admin metrics retrieved successfully", "application/json", AdminMetricsSchemas.AdminMetricsResponse},
      503 => {"Metrics unavailable", "application/json", CommonSchemas.GenericErrorResponse}
    }
  )

  @doc """
  Returns admin application metrics (PromEx).
  """
  def show_self(conn, _params) do
    with {:ok, metrics} <- AdminMetrics.get() do
      render(conn, :show_self, metrics: metrics)
    end
  end
end
