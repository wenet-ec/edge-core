# edge_admin/lib/edge_admin_web/controllers/commands/command_execution_controller.ex
defmodule EdgeAdminWeb.Controllers.Commands.CommandExecutionController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Commands
  alias EdgeAdminWeb.Schemas.Commands.CommandExecutionSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EdgeAdminWeb.Plugs.CastAndValidateErrorRenderer
  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index, :show, :delete, :cancel]

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
        description: "Comma-separated list of sort directions (asc/desc) corresponding to order_by fields",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "desc,asc"
      ],
      status: [
        in: :query,
        description: "Filter by execution status",
        schema: %OpenApiSpex.Schema{type: :string, enum: ["pending", "sent", "completed", "cancelled", "expired"]}
      ],
      target_all: [
        in: :query,
        description: "Filter by target_all flag",
        schema: %OpenApiSpex.Schema{type: :boolean}
      ],
      exit_code: [
        in: :query,
        description: "Filter by exact exit code",
        schema: %OpenApiSpex.Schema{type: :integer}
      ],
      exit_code__gte: [
        in: :query,
        description: "Filter executions with exit code greater than or equal to this value (e.g. 1 for all failures)",
        schema: %OpenApiSpex.Schema{type: :integer}
      ],
      exit_code__lte: [
        in: :query,
        description: "Filter executions with exit code less than or equal to this value",
        schema: %OpenApiSpex.Schema{type: :integer}
      ],
      has_output: [
        in: :query,
        description:
          "Filter by whether output is present: true returns executions with output, false returns executions with no output",
        schema: %OpenApiSpex.Schema{type: :boolean}
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
        description: "Text search in output (exact match or wildcard: *error*, *failed, etc.)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      cluster_name: [
        in: :query,
        description: "Filter by cluster name via node's cluster (exact match or wildcard: prod*, *staging, etc.)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      has_cluster: [
        in: :query,
        description: "Filter by cluster_id presence (true = cluster-wide executions, false = non-cluster-wide)",
        schema: %OpenApiSpex.Schema{type: :boolean}
      ],
      inserted_at__gte: [
        in: :query,
        description:
          "Filter command executions inserted after this datetime (e.g. 2025-01-01T00:00:00Z; date-only 2025-01-01 is treated as start of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      inserted_at__lte: [
        in: :query,
        description:
          "Filter command executions inserted before this datetime (e.g. 2025-01-01T23:59:59Z; date-only 2025-01-01 is treated as end of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      updated_at__gte: [
        in: :query,
        description:
          "Filter command executions updated after this datetime (e.g. 2025-01-01T00:00:00Z; date-only 2025-01-01 is treated as start of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      updated_at__lte: [
        in: :query,
        description:
          "Filter command executions updated before this datetime (e.g. 2025-01-01T23:59:59Z; date-only 2025-01-01 is treated as end of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      sent_at__gte: [
        in: :query,
        description:
          "Filter command executions sent after this datetime (e.g. 2025-01-01T00:00:00Z; date-only 2025-01-01 is treated as start of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      sent_at__lte: [
        in: :query,
        description:
          "Filter command executions sent before this datetime (e.g. 2025-01-01T23:59:59Z; date-only 2025-01-01 is treated as end of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      completed_at__gte: [
        in: :query,
        description:
          "Filter command executions completed after this datetime (e.g. 2025-01-01T00:00:00Z; date-only 2025-01-01 is treated as start of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      completed_at__lte: [
        in: :query,
        description:
          "Filter command executions completed before this datetime (e.g. 2025-01-01T23:59:59Z; date-only 2025-01-01 is treated as end of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      cancelled_at__gte: [
        in: :query,
        description:
          "Filter command executions cancelled after this datetime (e.g. 2025-01-01T00:00:00Z; date-only 2025-01-01 is treated as start of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      cancelled_at__lte: [
        in: :query,
        description:
          "Filter command executions cancelled before this datetime (e.g. 2025-01-01T23:59:59Z; date-only 2025-01-01 is treated as end of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ]
    ],
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
    parameters: [
      id: [
        in: :path,
        description: "Command Execution ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
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
    parameters: [
      id: [
        in: :path,
        description: "Command Execution ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
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
    parameters: [
      id: [
        in: :path,
        description: "Command Execution ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Cancellation request sent", "application/json", CommandExecutionSchemas.CancelExecutionResponse},
      404 => {"Command execution not found", "application/json", CommonSchemas.NotFoundResponse},
      422 =>
        {"Validation failed - execution status not cancellable", "application/json",
         CommonSchemas.ChangesetErrorResponse},
      503 => {"Service Unavailable", "application/json", CommonSchemas.ServiceUnavailableResponse}
    }
  )

  def cancel(conn, %{id: id}) do
    with {:ok, execution} <- Commands.get_command_execution(id),
         {:ok, result} <- Commands.cancel_command_execution(execution) do
      render(conn, :cancel, conn: conn, result: result)
    end
  end
end
