# edge_admin/lib/edge_admin_web/controllers/agents/metrics_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.MetricsController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Metrics
  alias EdgeAdmin.Metrics.Forms.PushMetricsCacheForm
  alias EdgeAdminWeb.Schemas.Agents.MetricsSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true
  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:push]

  tags(["Internal.Agents"])

  operation(:push,
    summary: "Push metrics cache",
    description:
      "Agent pushes metrics to admin when VPN is unavailable. Metrics are cached temporarily and served to collectors. Node ID is inferred from the API token.",
    request_body: {"Metrics payload", "application/json", MetricsSchemas.MetricsCachePushRequest, required: true},
    responses: %{
      200 => {"Metrics cache updated", "application/json", MetricsSchemas.MetricsCachePushResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse}
    }
  )

  def push(conn, params) do
    node = conn.assigns.current_node
    merged = Map.merge(params, conn.body_params)

    with {:ok, validated_attrs} <- PushMetricsCacheForm.changeset(merged),
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
