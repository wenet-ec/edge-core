# edge_admin/lib/edge_admin_web/controllers/metrics/host_metrics_controller.ex
defmodule EdgeAdminWeb.Controllers.Metrics.HostMetricsController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Metrics
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true
  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:show]

  tags(["Internal.Metrics"])

  operation(:show,
    summary: "Raw host metrics proxy",
    description: "Scrapes Prometheus metrics from a node's Node Exporter via Gateway and returns raw text format.",
    parameters: [
      node_id: [
        in: :path,
        description: "Node UUID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Raw Prometheus metrics text", "text/plain", %OpenApiSpex.Schema{type: :string}},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Invalid path parameters", "application/json", OpenApiSpex.JsonErrorResponse},
      503 => {"Metrics unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def show(conn, %{node_id: node_id}) do
    with {:ok, metrics_text} <- Metrics.scrape_host_metrics(node_id) do
      conn
      |> put_resp_content_type("text/plain; version=0.0.4")
      |> send_resp(200, metrics_text)
    end
  end
end
