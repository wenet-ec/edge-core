# edge_admin/lib/edge_admin_web/controllers/commands/command_controller.ex
defmodule EdgeAdminWeb.Controllers.Commands.CommandController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Commands
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdminWeb.Schemas.Commands.CommandSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EdgeAdminWeb.Plugs.CastAndValidateErrorRenderer
  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index, :show, :create, :delete]

  tags(["Commands.Command"])

  operation(:index,
    summary: "List all commands",
    description: "Returns a paginated list of all commands with filtering and sorting",
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
        example: "inserted_at"
      ],
      order_directions: [
        in: :query,
        description: "Comma-separated list of sort directions (asc/desc) corresponding to order_by fields",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "desc"
      ],
      command_text: [
        in: :query,
        description: "Filter by command text (exact match or wildcard: ls*, *docker*, etc.)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      timeout__gte: [
        in: :query,
        description: "Filter commands with timeout greater than or equal to this value (milliseconds)",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 1}
      ],
      timeout__lte: [
        in: :query,
        description: "Filter commands with timeout less than or equal to this value (milliseconds)",
        schema: %OpenApiSpex.Schema{type: :integer, minimum: 1}
      ],
      has_timeout: [
        in: :query,
        description:
          "Filter by whether a timeout is set: true returns commands with a timeout, false returns commands with no timeout",
        schema: %OpenApiSpex.Schema{type: :boolean}
      ],
      expired_at__gte: [
        in: :query,
        description: "Filter commands with expired_at after this datetime",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      expired_at__lte: [
        in: :query,
        description: "Filter commands with expired_at before this datetime",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ],
      has_expired_at: [
        in: :query,
        description:
          "Filter by whether an expiration is set: true returns commands with expired_at, false returns commands without",
        schema: %OpenApiSpex.Schema{type: :boolean}
      ],
      inserted_at__gte: [
        in: :query,
        description:
          "Filter commands inserted after this datetime (e.g. 2025-01-01T00:00:00Z; date-only 2025-01-01 is treated as start of day UTC)",
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
          "Filter commands inserted before this datetime (e.g. 2025-01-01T23:59:59Z; date-only 2025-01-01 is treated as end of day UTC)",
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
          "Filter commands updated after this datetime (e.g. 2025-01-01T00:00:00Z; date-only 2025-01-01 is treated as start of day UTC)",
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
          "Filter commands updated before this datetime (e.g. 2025-01-01T23:59:59Z; date-only 2025-01-01 is treated as end of day UTC)",
        schema: %OpenApiSpex.Schema{
          anyOf: [
            %OpenApiSpex.Schema{type: :string, format: :"date-time"},
            %OpenApiSpex.Schema{type: :string, format: :date}
          ]
        }
      ]
    ],
    responses: %{
      200 => {"Paginated list of commands", "application/json", CommandSchemas.CommandPaginatedResponse},
      400 => {"Invalid query parameters", "application/json", CommonSchemas.BadRequestResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {commands, meta}} <- Commands.list_commands(params) do
      render(conn, :index, conn: conn, commands: commands, meta: meta)
    end
  end

  operation(:create,
    summary: "Create a new command",
    description: """
    Create a new command for execution on nodes using flexible targeting options.

    Targeting types:
    - 'all': Target all nodes (with optional filters)
    - 'nodes': Target specific nodes by IDs (with optional filters)
    - 'clusters': Target specific clusters by names (with optional filters)

    Node and cluster filters can be applied to further refine targeting.
    """,
    request_body:
      {"Command creation parameters", "application/json", CommandSchemas.CommandCreateRequest, required: true},
    responses: %{
      201 => {"Command created successfully", "application/json", CommandSchemas.CommandSingleResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse}
    }
  )

  def create(conn, params) do
    with {:ok, %Command{} = command} <-
           Commands.create_command_and_executions(Map.merge(params, conn.body_params)) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/commands/#{command}")
      |> render(:show, conn: conn, command: command)
    end
  end

  operation(:show,
    summary: "Get a specific command",
    description: "Returns details for a specific command by ID",
    parameters: [
      id: [
        in: :path,
        description: "Command ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Command details", "application/json", CommandSchemas.CommandSingleResponse},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Command not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{id: id}) do
    with {:ok, command} <- Commands.get_command(id) do
      render(conn, :show, conn: conn, command: command)
    end
  end

  operation(:delete,
    summary: "Delete a command",
    description: """
    Delete a command and all its related command executions (cascaded deletion).

    Only commands where ALL executions are completed can be deleted.
    Attempting to delete a command with pending or sent executions will return 409.
    """,
    parameters: [
      id: [
        in: :path,
        description: "Command ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      204 => {"Command deleted successfully", "", nil},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"Command not found", "application/json", CommonSchemas.NotFoundResponse},
      409 => {"Cannot delete command with non-completed executions", "application/json", CommonSchemas.ConflictResponse}
    }
  )

  def delete(conn, %{id: id}) do
    with {:ok, command} <- Commands.get_command(id),
         {:ok, _command} <- Commands.delete_command(command) do
      send_resp(conn, :no_content, "")
    end
  end
end
