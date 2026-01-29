# edge_admin/lib/edge_admin_web/controllers/metrics/wireguard_metrics_controller.ex
defmodule EdgeAdminWeb.Controllers.Metrics.WireguardMetricsController do
  use EdgeAdminWeb, :controller

  alias EdgeAdmin.Metrics

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:show]

  @doc """
  Raw WireGuard metrics proxy endpoint.
  Scrapes Prometheus metrics from a node's WireGuard Exporter endpoint via Gateway and returns raw text format.

  This endpoint is NOT documented in Swagger.
  """
  def show(conn, %{"node_id" => node_id}) do
    with {:ok, metrics_text} <- Metrics.scrape_wireguard_metrics(node_id) do
      conn
      |> put_resp_content_type("text/plain; version=0.0.4")
      |> send_resp(200, metrics_text)
    end
  end
end
