# edge_admin/lib/edge_admin_web/controllers/nodes/ssh_username_controller.ex
defmodule EdgeAdminWeb.Nodes.SshUsernameController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.SshUsername
  alias EdgeAdminWeb.Schemas.Nodes.SshUsernameSchemas
  alias EdgeAdminWeb.Schemas.CommonSchemas

  action_fallback(EdgeAdminWeb.FallbackController)

  tags(["Nodes.SshUsername"])

  operation(:index,
    summary: "List SSH usernames",
    description: "Returns a paginated list of SSH usernames with filtering and sorting",
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
      username: [
        in: :query,
        description: "Filter by username (supports wildcards with *)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      node_id: [
        in: :query,
        description: "Filter by node ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 =>
        {"Paginated list of SSH usernames", "application/json",
         SshUsernameSchemas.SshUsernamePaginatedResponse}
    }
  )

  def index(conn, params) do
    page_result = Nodes.list_ssh_usernames_with_filtering_pagination(params)
    render(conn, :index, page_result: page_result)
  end

  operation(:create,
    summary: "Create SSH username",
    description: "Create a new SSH username for a specific node",
    parameters: [
      node_id: [
        in: :path,
        description: "Node ID to create SSH username for",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    request_body:
      {"SSH username creation data", "application/json",
       SshUsernameSchemas.SshUsernameCreateRequest},
    responses: %{
      201 =>
        {"SSH username created", "application/json", SshUsernameSchemas.SshUsernameSingleResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ErrorResponse}
    }
  )

  def create(conn, %{"node_id" => node_id, "ssh_username" => ssh_username_params}) do
    ssh_username_params = Map.put(ssh_username_params, "node_id", node_id)

    with {:ok, %SshUsername{} = ssh_username} <- Nodes.create_ssh_username(ssh_username_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/ssh_usernames/#{ssh_username}")
      |> render(:show, ssh_username: ssh_username)
    end
  end

  operation(:show,
    summary: "Get SSH username",
    description: "Get a specific SSH username by ID",
    parameters: [
      id: [
        in: :path,
        description: "SSH username ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 =>
        {"SSH username details", "application/json", SshUsernameSchemas.SshUsernameSingleResponse},
      404 => {"SSH username not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{"id" => id}) do
    ssh_username = Nodes.get_ssh_username!(id)
    render(conn, :show, ssh_username: ssh_username)
  end

  operation(:delete,
    summary: "Delete SSH username",
    description: "Delete a SSH username and all associated public keys",
    parameters: [
      id: [
        in: :path,
        description: "SSH username ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      204 => {"SSH username deleted", "application/json", nil},
      404 => {"SSH username not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def delete(conn, %{"id" => id}) do
    ssh_username = Nodes.get_ssh_username!(id)

    with {:ok, %SshUsername{}} <- Nodes.delete_ssh_username(ssh_username) do
      send_resp(conn, :no_content, "")
    end
  end
end
