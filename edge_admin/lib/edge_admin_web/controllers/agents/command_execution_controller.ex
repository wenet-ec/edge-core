# edge_admin/lib/edge_admin_web/controllers/agents/command_execution_controller.ex
defmodule EdgeAdminWeb.Controllers.Agents.CommandExecutionController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Commands
  alias EdgeAdmin.Commands.Policies.CommandExecutionPolicy
  alias EdgeAdminWeb.Schemas.Agents.CommandExecutionSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback EdgeAdminWeb.Controllers.FallbackController

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EdgeAdminWeb.Plugs.CastAndValidateErrorRenderer
  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index, :acknowledge, :update_result]

  tags(["Internal.Agents"])

  operation(:index,
    summary: "List command executions for this node",
    description:
      "Agent fetches command executions with optional filtering and pagination. Node ID is inferred from the API token.",
    parameters: [
      status: [
        in: :query,
        description: "Filter by status: sent, pending, completed, cancelled, or expired",
        schema: %OpenApiSpex.Schema{type: :string, enum: ["sent", "pending", "completed", "cancelled", "expired"]},
        required: true
      ],
      page: [
        in: :query,
        description: "Page number",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 1, default: 1}
      ],
      page_size: [
        in: :query,
        description: "Items per page",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 1, maximum: 100, default: 100}
      ],
      order_by: [
        in: :query,
        description: "Field to sort by",
        schema: %OpenApiSpex.Schema{type: :string, default: "inserted_at"}
      ],
      order_directions: [
        in: :query,
        description: "Sort direction: asc or desc",
        schema: %OpenApiSpex.Schema{type: :string, enum: ["asc", "desc"], default: "asc"}
      ]
    ],
    responses: %{
      200 =>
        {"Command executions list", "application/json", CommandExecutionSchemas.AgentCommandExecutionPaginatedResponse},
      400 => {"Invalid query parameters", "application/json", CommonSchemas.BadRequestResponse}
    }
  )

  def index(conn, params) do
    node_id = conn.assigns.current_node.id

    query_params =
      params
      |> Map.put(:node_id, node_id)
      |> Map.put_new(:order_by, "inserted_at")
      |> Map.put_new(:order_directions, "asc")
      |> Map.put_new(:page_size, 100)

    with {:ok, {command_executions, meta}} <- Commands.list_command_executions(query_params) do
      render(conn, :index, conn: conn, command_executions: command_executions, meta: meta)
    end
  end

  operation(:acknowledge,
    summary: "Acknowledge a command execution",
    description: "Agent acknowledges receipt of a pending command execution. Transitions status from pending to sent.",
    parameters: [
      id: [
        in: :path,
        description: "Command execution UUID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 =>
        {"Command execution acknowledged", "application/json",
         CommandExecutionSchemas.AgentCommandExecutionSingleResponse},
      403 => {"Forbidden", "application/json", CommonSchemas.ForbiddenResponse},
      404 => {"Not found", "application/json", CommonSchemas.NotFoundResponse},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse}
    }
  )

  def acknowledge(conn, %{id: id} = params) do
    with {:ok, execution} <- Commands.get_command_execution(id),
         :ok <- CommandExecutionPolicy.authorize({:update, conn.assigns.current_node, execution}),
         {:ok, updated_execution} <- Commands.acknowledge_execution(execution, params) do
      render(conn, :show, conn: conn, command_execution: updated_execution)
    end
  end

  operation(:update_result,
    summary: "Report command execution result",
    description:
      "Agent reports command results (output, exit_code, status). Verifies command belongs to the authenticated node.",
    parameters: [
      id: [
        in: :path,
        description: "Command execution UUID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    request_body:
      {"Command execution result", "application/json", CommandExecutionSchemas.UpdateCommandExecutionResultRequest,
       required: true},
    responses: %{
      200 =>
        {"Command execution updated", "application/json", CommandExecutionSchemas.AgentCommandExecutionSingleResponse},
      403 => {"Forbidden", "application/json", CommonSchemas.ForbiddenResponse},
      404 => {"Not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse}
    }
  )

  def update_result(conn, %{id: id}) do
    with {:ok, execution} <- Commands.get_command_execution(id),
         :ok <- CommandExecutionPolicy.authorize({:update, conn.assigns.current_node, execution}),
         {:ok, updated_execution} <-
           Commands.update_command_execution_result(execution, conn.body_params) do
      render(conn, :show, conn: conn, command_execution: updated_execution)
    end
  end
end
