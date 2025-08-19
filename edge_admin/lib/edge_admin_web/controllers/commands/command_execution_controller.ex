# edge_admin/lib/edge_admin_web/controllers/commands/command_execution_controller.ex
defmodule EdgeAdminWeb.Commands.CommandExecutionController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Commands
  alias EdgeAdmin.Commands.CommandExecution
  alias EdgeAdminWeb.Schemas.Commands.CommandExecutionSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.FallbackController)

  tags(["Commands.CommandExecution"])

  operation(:index,
    summary: "List command executions",
    description: "Returns a paginated list of command executions with filtering and sorting",
    parameters: [
      page: [
        in: :query,
        description: "Page number",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 1, default: 1},
        example: 1
      ],
      page_size: [
        in: :query,
        description: "Items per page",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 1, maximum: 100, default: 20},
        example: 20
      ],
      sort: [
        in: :query,
        description: "Sort specification: field1:dir1,field2:dir2",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "inserted_at:desc"
      ],
      status: [
        in: :query,
        description: "Filter by execution status",
        schema: %OpenApiSpex.Schema{type: :string, enum: ["pending", "sent", "completed"]}
      ],
      target_all: [
        in: :query,
        description: "Filter by target_all flag",
        schema: %OpenApiSpex.Schema{type: :boolean}
      ],
      exit_code: [
        in: :query,
        description: "Filter by exit code (supports ranges like 'gte:0', 'ne:0')",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      command_id: [
        in: :query,
        description: "Filter by command ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ],
      node_id: [
        in: :query,
        description: "Filter by node ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ],
      output: [
        in: :query,
        description: "Text search in output (supports wildcards with *)",
        schema: %OpenApiSpex.Schema{type: :string}
      ]
    ],
    responses: %{
      200 =>
        {"Paginated list of command executions", "application/json",
         CommandExecutionSchemas.CommandExecutionPaginatedResponse}
    }
  )

  def index(conn, params) do
    page_result = Commands.list_command_executions_with_filtering_pagination(params)
    render(conn, :index, page_result: page_result)
  end

  operation(:show,
    summary: "Get a specific command execution",
    description: "Returns details for a specific command execution by ID",
    parameters: [
      id: [
        in: :path,
        description: "Command Execution ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Command execution details", "application/json", CommandExecutionSchemas.CommandExecutionSingleResponse},
      404 => {"Command execution not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{"id" => id}) do
    command_execution = Commands.get_command_execution!(id)
    render(conn, :show, command_execution: command_execution)
  end

  operation(:update,
    summary: "Update command execution",
    description: "Update command execution results (typically called by agents)",
    parameters: [
      id: [
        in: :path,
        description: "Command Execution ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    request_body:
      {"Command execution update", "application/json", CommandExecutionSchemas.CommandExecutionUpdateRequest},
    responses: %{
      200 =>
        {"Command execution updated successfully", "application/json",
         CommandExecutionSchemas.CommandExecutionSingleResponse},
      404 => {"Command execution not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ErrorResponse}
    }
  )

  def update(conn, %{"id" => id, "command_execution" => command_execution_params}) do
    command_execution = Commands.get_command_execution!(id)

    with {:ok, %CommandExecution{} = updated_execution} <-
           Commands.update_command_execution(command_execution, command_execution_params) do
      final_execution = Commands.get_command_execution!(updated_execution.id)
      render(conn, :show, command_execution: final_execution)
    end
  end
end
