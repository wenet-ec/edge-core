# edge_admin/lib/edge_admin_web/controllers/metrics/human_metrics_json.ex
defmodule EdgeAdminWeb.Controllers.Metrics.HumanMetricsJSON do
  @moduledoc """
  JSON views for human-friendly metrics endpoints
  """

  @doc """
  Renders unified metrics from all sources.
  """
  def show_unified(%{metrics: metrics}) do
    %{data: metrics}
  end

  @doc """
  Renders host-only metrics.
  """
  def show_host(%{metrics: metrics}) do
    %{data: metrics}
  end
end
