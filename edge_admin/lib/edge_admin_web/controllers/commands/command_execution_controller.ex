# edge_admin/lib/edge_admin_web/controllers/commands/command_execution_controller.ex
defmodule EdgeAdminWeb.Controllers.Commands.CommandExecutionController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Commands
  alias EdgeAdminWeb.Schemas.Commands.CommandExecutionSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

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
      order_by: [
        in: :query,
        description: "Comma-separated list of fields to sort by",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "inserted_at,status"
      ],
      order_directions: [
        in: :query,
        description:
          "Comma-separated list of sort directions (asc/desc) corresponding to order_by fields",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "desc,asc"
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
        description: "Filter by exit code",
        schema: %OpenApiSpex.Schema{type: :integer}
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
        description:
          "Text search in output (exact match or wildcard: *error*, *failed, etc.)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      cluster_name: [
        in: :query,
        description:
          "Filter by cluster name via node's cluster (exact match or wildcard: prod*, *staging, etc.)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      has_cluster: [
        in: :query,
        description:
          "Filter by cluster_id presence (true = cluster-wide executions, false = non-cluster-wide)",
        schema: %OpenApiSpex.Schema{type: :boolean}
      ],
      inserted_at__gte: [
        in: :query,
        description: "Filter command executions inserted after or on this date",
        schema: %OpenApiSpex.Schema{type: :string, format: :date}
      ],
      inserted_at__lte: [
        in: :query,
        description: "Filter command executions inserted before or on this date",
        schema: %OpenApiSpex.Schema{type: :string, format: :date}
      ]
    ],
    responses: %{
      200 =>
        {"Paginated list of command executions", "application/json",
         CommandExecutionSchemas.CommandExecutionPaginatedResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {command_executions, meta}} <- Commands.list_command_executions(params) do
      render(conn, :index, command_executions: command_executions, meta: meta)
    end
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
      200 =>
        {"Command execution details", "application/json",
         CommandExecutionSchemas.CommandExecutionSingleResponse},
      404 => {"Command execution not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{"id" => id}) do
    with {:ok, command_execution} <- Commands.get_command_execution(id) do
      render(conn, :show, command_execution: command_execution)
    end
  end

  operation(:delete,
    summary: "Delete a command execution",
    description: "Delete a specific command execution",
    parameters: [
      id: [
        in: :path,
        description: "Command Execution ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      204 => {"Command execution deleted successfully", "", nil},
      404 => {"Command execution not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def delete(conn, %{"id" => id}) do
    with {:ok, command_execution} <- Commands.get_command_execution(id),
         {:ok, _command_execution} <- Commands.delete_command_execution(command_execution) do
      send_resp(conn, :no_content, "")
    end
  end
end
