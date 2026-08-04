# edge_admin/lib/edge_admin_web/controllers/agents/node_diagnostic_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.NodeDiagnosticController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Forms.PushNodeDiagnosticForm
  alias EdgeAdminWeb.Plugs.DegradedMode
  alias EdgeAdminWeb.Schemas.Agents.NodeDiagnosticSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  plug DegradedMode, :allow when action in [:push]

  tags(["Internal.Agents"])

  operation(:push,
    summary: "Push diagnostics",
    description:
      "Agent pushes its latest diagnostic report through HTTP fallback. Node ID is inferred from the Agent API token; this updates diagnostics only and never changes node health status.",
    request_body:
      {"Diagnostic snapshot", "application/json", NodeDiagnosticSchemas.NodeDiagnosticPushRequest, required: true},
    responses: %{
      200 => {"Diagnostics pushed", "application/json", NodeDiagnosticSchemas.NodeDiagnosticPushResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse}
    }
  )

  def push(conn, params) do
    node = conn.assigns.current_node
    merged = Map.merge(params, conn.body_params)

    with {:ok, validated_attrs} <- PushNodeDiagnosticForm.changeset(merged),
         {:ok, cached_diagnostic} <-
           Nodes.upsert_node_diagnostic(node.id, validated_attrs["diagnostic"]) do
      render(conn, :show, conn: conn, diagnostic: cached_diagnostic)
    end
  end
end
