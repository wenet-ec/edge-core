# edge_admin/lib/edge_admin_web/controllers/metrics/admin_metrics_json.ex
defmodule EdgeAdminWeb.Controllers.Metrics.AdminMetricsJSON do
  @moduledoc """
  JSON views for admin metrics endpoints
  """

  @doc """
  Renders admin application metrics.
  """
  def show_self(%{metrics: metrics}) do
    %{data: metrics}
  end
end
