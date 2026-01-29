# edge_admin/lib/edge_admin_web/controllers/agents/metrics_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.MetricsController do
  use EdgeAdminWeb, :controller

  alias EdgeAdmin.Metrics
  alias EdgeAdmin.Metrics.Forms.PushMetricsCacheForm

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:push]

  @doc """
  Metrics push endpoint for HTTP fallback mode.

  Agent pushes metrics to admin when VPN is unavailable. Metrics are cached
  temporarily and served to collectors when they scrape admin endpoints.

  Node ID is inferred from conn.assigns.current_node (authenticated via API token).
  """
  def push(conn, params) do
    # Get node from authenticated context (set by AgentAuth plug)
    node = conn.assigns.current_node

    with {:ok, validated_attrs} <- PushMetricsCacheForm.changeset(params),
         {:ok, cache} <-
           Metrics.upsert_metrics_cache(
             node.id,
             validated_attrs["metrics_type"],
             validated_attrs["metrics_text"]
           ) do
      render(conn, :show, cache: cache)
    end
  end
end
