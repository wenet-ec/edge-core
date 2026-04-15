# edge_admin/lib/edge_admin_web/controllers/metrics/admin_metrics_json.ex
defmodule EdgeAdminWeb.Controllers.Metrics.AdminMetricsJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def show_self(%{conn: conn, metrics: metrics}) do
    ResponseEnvelope.success(conn, metrics)
  end
end
