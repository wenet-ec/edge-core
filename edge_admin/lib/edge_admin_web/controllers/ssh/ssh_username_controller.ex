# edge_admin/lib/edge_admin_web/controllers/ssh/ssh_username_controller.ex
defmodule EdgeAdminWeb.Controllers.Ssh.SshUsernameController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Ssh
  alias EdgeAdmin.Ssh.Schemas.SshUsername
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Ssh.SshUsernameSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index, :show, :create, :delete]

  tags(["Ssh.SshUsername"])

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
      order_by: [
        in: :query,
        description: "Comma-separated list of fields to sort by",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "inserted_at,username"
      ],
      order_directions: [
        in: :query,
        description: "Comma-separated list of sort directions (asc/desc) corresponding to order_by fields",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "desc,asc"
      ],
      username: [
        in: :query,
        description: "Filter by username (exact match or wildcard: root*, *admin, etc.)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      node_id: [
        in: :query,
        description: "Filter by node ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ],
      has_password: [
        in: :query,
        description: "Filter by whether username has password configured",
        schema: %OpenApiSpex.Schema{type: :boolean}
      ],
      inserted_at__gte: [
        in: :query,
        description: "Filter SSH usernames inserted after or on this date",
        schema: %OpenApiSpex.Schema{type: :string, format: :date}
      ],
      inserted_at__lte: [
        in: :query,
        description: "Filter SSH usernames inserted before or on this date",
        schema: %OpenApiSpex.Schema{type: :string, format: :date}
      ]
    ],
    responses: %{
      200 => {"Paginated list of SSH usernames", "application/json", SshUsernameSchemas.SshUsernamePaginatedResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {ssh_usernames, meta}} <- Ssh.list_ssh_usernames(params) do
      render(conn, :index, ssh_usernames: ssh_usernames, meta: meta)
    end
  end

  operation(:create,
    summary: "Create SSH username",
    description: "Create a new SSH username for a specific node, optionally with public keys and/or password",
    parameters: [
      node_id: [
        in: :path,
        description: "Node ID to create SSH username for",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    request_body: {"SSH username creation data", "application/json", SshUsernameSchemas.SshUsernameCreateRequest},
    responses: %{
      201 => {"SSH username created", "application/json", SshUsernameSchemas.SshUsernameSingleResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse}
    }
  )

  def create(conn, %{"node_id" => node_id} = params) do
    with {:ok, node} <- Nodes.get_node(node_id),
         {:ok, %SshUsername{} = ssh_username} <- Ssh.create_ssh_username_with_keys(node, params) do
      # Ensure keys are loaded for response
      ssh_username = EdgeAdmin.Repo.preload(ssh_username, :ssh_public_keys)

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
      200 => {"SSH username details", "application/json", SshUsernameSchemas.SshUsernameSingleResponse},
      404 => {"SSH username not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{"id" => id}) do
    with {:ok, ssh_username} <- Ssh.get_ssh_username(id) do
      render(conn, :show, ssh_username: ssh_username)
    end
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
    with {:ok, ssh_username} <- Ssh.get_ssh_username(id),
         {:ok, %SshUsername{}} <- Ssh.delete_ssh_username(ssh_username) do
      send_resp(conn, :no_content, "")
    end
  end
end
