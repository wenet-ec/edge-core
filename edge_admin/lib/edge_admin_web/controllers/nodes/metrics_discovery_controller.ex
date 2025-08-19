# lib/edge_admin_web/controllers/nodes/metrics_discovery_controller.ex
defmodule EdgeAdminWeb.Controllers.Nodes.MetricsDiscoveryController do
  use EdgeAdminWeb, :controller

  alias EdgeAdmin.Nodes

  @doc """
  Service discovery endpoint for vmagent HTTP SD.
  Returns all active nodes in the format expected by vmagent http_sd_configs.

  This endpoint is NOT documented in Swagger as requested.
  """
  def index(conn, _params) do
    targets = Nodes.list_metrics_discovery_targets()
    render(conn, :index, targets: targets)
  end
end
