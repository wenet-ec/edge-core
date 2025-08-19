# edge_admin/lib/edge_admin_web/controllers/commands/command_controller.ex
defmodule EdgeAdminWeb.Controllers.Commands.CommandController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Commands
  alias EdgeAdmin.Commands.Command
  alias EdgeAdminWeb.Schemas.Commands.CommandSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

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
      sort: [
        in: :query,
        description: "Sort specification: field1:dir1,field2:dir2",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "inserted_at:desc"
      ],
      command_text: [
        in: :query,
        description: "Filter by command text (supports wildcards with *)",
        schema: %OpenApiSpex.Schema{type: :string}
      ]
    ],
    responses: %{
      200 => {"Paginated list of commands", "application/json", CommandSchemas.CommandPaginatedResponse}
    }
  )

  def index(conn, params) do
    page_result = Commands.list_commands_with_filtering_pagination(params)
    render(conn, :index, page_result: page_result)
  end

  operation(:create,
    summary: "Create a new command",
    description: """
    Create a new command for execution on nodes using flexible targeting options.

    Targeting types:
    - 'all': Target all nodes, optionally with node_filters
    - 'nodes': Target specific nodes by IDs, optionally with node_filters

    Node filters can be applied to any targeting type to further refine which nodes receive the command.
    """,
    request_body: {"Command creation parameters", "application/json", CommandSchemas.CommandCreateRequest},
    responses: %{
      201 => {"Command created successfully", "application/json", CommandSchemas.CommandSingleResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ErrorResponse}
    }
  )

  def create(conn, %{"command" => command_params}) do
    with {:ok, %Command{} = command} <-
           Commands.create_command_and_dispatch_executions(command_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/commands/#{command}")
      |> render(:show, command: command)
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
      404 => {"Command not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{"id" => id}) do
    command = Commands.get_command!(id)
    render(conn, :show, command: command)
  end
end
