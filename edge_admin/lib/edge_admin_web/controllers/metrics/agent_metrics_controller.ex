# edge_admin/lib/edge_admin_web/controllers/metrics/agent_metrics_controller.ex
defmodule EdgeAdminWeb.Controllers.Metrics.AgentMetricsController do
  use EdgeAdminWeb, :controller

  alias EdgeAdmin.Metrics.AgentMetrics

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  @doc """
  Raw agent metrics proxy endpoint.
  Scrapes Prometheus metrics from a node's PromEx endpoint via Gateway and returns raw text format.

  This endpoint is NOT documented in Swagger.
  """
  def show(conn, %{"node_id" => node_id}) do
    with {:ok, metrics_text} <- AgentMetrics.scrape_raw(node_id) do
      conn
      |> put_resp_content_type("text/plain; version=0.0.4")
      |> send_resp(200, metrics_text)
    end
  end
end
