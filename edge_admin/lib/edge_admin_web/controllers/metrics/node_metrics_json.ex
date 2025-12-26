# edge_admin/lib/edge_admin_web/controllers/metrics/node_metrics_json.ex
defmodule EdgeAdminWeb.Controllers.Metrics.NodeMetricsJSON do
  @moduledoc """
  JSON views for node metrics endpoints
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

  @doc """
  Renders agent application metrics.
  """
  def show_agent(%{metrics: metrics}) do
    %{data: metrics}
  end
end
