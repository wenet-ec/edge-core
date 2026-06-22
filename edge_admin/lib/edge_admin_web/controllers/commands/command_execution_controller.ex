# edge_admin/lib/edge_admin_web/controllers/commands/command_execution_controller.ex
defmodule EdgeAdminWeb.Controllers.Commands.CommandExecutionController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Commands
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdminWeb.Schemas.Commands.CommandExecutionSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.PathParams
  alias EdgeAdminWeb.Schemas.QueryParams

  @status_enum CommandExecution.status_strings()

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index, :show, :delete, :cancel]

  tags(["Commands.CommandExecution"])

  operation(:index,
    summary: "List command executions",
    description: "Returns a paginated list of command executions with filtering and sorting",
    parameters:
      QueryParams.pagination() ++
        QueryParams.sort(order_by_example: "inserted_at,status", order_directions_example: "desc,asc") ++
        [
          QueryParams.enum_in_filter(:status, @status_enum,
            description: "Filter by execution status (e.g. status__in=pending,sent)"
          ),
          QueryParams.boolean_filter(:target_all, description: "Filter by target_all flag"),
          QueryParams.int_filter(:exit_code, description: "Filter by exact exit code"),
          QueryParams.boolean_filter(:has_output,
            description:
              "Filter by whether output is present: true returns executions with output, false returns executions with no output"
          ),
          QueryParams.uuid_in_filter(:command_id,
            description: "Filter by command IDs — comma-separated list of UUIDs (e.g. command_id__in=uuid1,uuid2)"
          ),
          QueryParams.uuid_in_filter(:node_id,
            description: "Filter by node IDs — comma-separated list of UUIDs (e.g. node_id__in=uuid1,uuid2)"
          ),
          QueryParams.string_filter(:output,
            description: "Text search in output (exact match or wildcard: *error*, *failed, etc.)"
          ),
          QueryParams.string_filter(:cluster_name,
            description: "Filter by cluster name via node's cluster — exact match or wildcard (prod*, *staging, *rod*)"
          ),
          QueryParams.string_in_filter(:cluster_name,
            description:
              "Filter by cluster name — comma-separated list for IN match (e.g. cluster_name__in=prod,staging)"
          ),
          QueryParams.boolean_filter(:has_cluster,
            description: "Filter by cluster_id presence (true = cluster-wide executions, false = non-cluster-wide)"
          )
        ] ++
        QueryParams.int_range_filter(:exit_code,
          gte_description:
            "Filter executions with exit code greater than or equal to this value (e.g. 1 for all failures)",
          lte_description: "Filter executions with exit code less than or equal to this value"
        ) ++
        QueryParams.datetime_range_filter(:inserted_at) ++
        QueryParams.datetime_range_filter(:updated_at) ++
        QueryParams.datetime_range_filter(:sent_at) ++
        QueryParams.datetime_range_filter(:completed_at) ++
        QueryParams.datetime_range_filter(:cancelled_at),
    responses: %{
      200 =>
        {"Paginated list of command executions", "application/json",
         CommandExecutionSchemas.CommandExecutionPaginatedResponse},
      400 => {"Invalid query parameters", "application/json", CommonSchemas.BadRequestResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {command_executions, meta}} <- Commands.list_command_executions(params) do
      render(conn, :index, conn: conn, command_executions: command_executions, meta: meta)
    end
  end

  operation(:show,
    summary: "Get a specific command execution",
    description: "Returns details for a specific command execution by ID",
    parameters: [PathParams.uuid(:id, "Command Execution ID")],
    responses: %{
      200 => {"Command execution details", "application/json", CommandExecutionSchemas.CommandExecutionSingleResponse},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Command execution not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{id: id}) do
    with {:ok, command_execution} <- Commands.get_command_execution(id) do
      render(conn, :show, conn: conn, command_execution: command_execution)
    end
  end

  operation(:delete,
    summary: "Delete a command execution",
    description: """
    Delete a specific command execution.

    Only completed, cancelled, or expired executions can be deleted. Attempting to delete pending or sent executions will return 409.
    """,
    parameters: [PathParams.uuid(:id, "Command Execution ID")],
    responses: %{
      204 => {"Command execution deleted successfully", "", nil},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Command execution not found", "application/json", CommonSchemas.NotFoundResponse},
      409 => {"Cannot delete non-completed execution", "application/json", CommonSchemas.ConflictResponse}
    }
  )

  def delete(conn, %{id: id}) do
    with {:ok, command_execution} <- Commands.get_command_execution(id),
         {:ok, _command_execution} <- Commands.delete_command_execution(command_execution) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:cancel,
    summary: "Cancel a command execution",
    description: """
    Attempts to cancel a command execution. Behavior depends on current status:

    - `pending`: Immediately marked `cancelled` in the database (command never ran).
    - `sent`: Sends cancellation request to agent (best-effort, async). The agent is the source of truth — if it already ran the command, it reports back the real result and the execution is marked `completed`. If the agent honoured the cancellation (exit code 143), it is marked `cancelled`.
    - `completed` / `cancelled`: Returns 409 conflict (already terminal).

    Returns 200 if cancellation was initiated. For `sent` executions, poll status to confirm the outcome.
    """,
    parameters: [PathParams.uuid(:id, "Command Execution ID")],
    responses: %{
      200 => {"Cancellation request sent", "application/json", CommandExecutionSchemas.CancelExecutionResponse},
      404 => {"Command execution not found", "application/json", CommonSchemas.NotFoundResponse},
      409 =>
        {"Execution not in a cancellable state (already terminal)", "application/json", CommonSchemas.ConflictResponse},
      503 =>
        {"Agent unreachable for cancellation request (sent status only)", "application/json",
         CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def cancel(conn, %{id: id}) do
    with {:ok, execution} <- Commands.get_command_execution(id),
         {:ok, result} <- Commands.cancel_command_execution(execution) do
      render(conn, :cancel, conn: conn, result: result)
    end
  end
end
