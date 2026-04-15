# edge_admin/lib/edge_admin_web/controllers/metrics/node_metrics_json.ex
defmodule EdgeAdminWeb.Controllers.Metrics.NodeMetricsJSON do
  alias EdgeAdminWeb.ResponseEnvelope

  def show_unified(%{conn: conn, metrics: metrics}) do
    ResponseEnvelope.success(conn, metrics)
  end

  def show_host(%{conn: conn, metrics: metrics}) do
    ResponseEnvelope.success(conn, metrics)
  end

  def show_agent(%{conn: conn, metrics: metrics}) do
    ResponseEnvelope.success(conn, metrics)
  end
end
