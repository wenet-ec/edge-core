# edge_admin/lib/edge_admin_web/controllers/commands/command_controller.ex
defmodule EdgeAdminWeb.Controllers.Commands.CommandController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Commands
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdminWeb.Schemas.Commands.CommandSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.PathParams
  alias EdgeAdminWeb.Schemas.QueryParams

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index, :show, :create, :delete]

  tags(["Commands.Command"])

  operation(:index,
    summary: "List all commands",
    description: "Returns a paginated list of all commands with filtering and sorting",
    parameters:
      QueryParams.pagination() ++
        QueryParams.sort() ++
        [
          QueryParams.string_filter(:command_text,
            description: "Filter by command text (exact match or wildcard: ls*, *docker*, etc.)"
          ),
          QueryParams.boolean_filter(:has_timeout,
            description:
              "Filter by whether a timeout is set: true returns commands with a timeout, false returns commands without"
          ),
          QueryParams.boolean_filter(:has_expired_at,
            description:
              "Filter by whether an expiration is set: true returns commands with expired_at, false returns commands without"
          )
        ] ++
        QueryParams.int_range_filter(:timeout,
          minimum: 1,
          gte_description: "Filter commands with timeout greater than or equal to this value (milliseconds)",
          lte_description: "Filter commands with timeout less than or equal to this value (milliseconds)"
        ) ++
        QueryParams.datetime_range_filter(:expired_at) ++
        QueryParams.datetime_range_filter(:inserted_at) ++
        QueryParams.datetime_range_filter(:updated_at),
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
    parameters: [PathParams.uuid(:id, "Command ID")],
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
    parameters: [PathParams.uuid(:id, "Command ID")],
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
