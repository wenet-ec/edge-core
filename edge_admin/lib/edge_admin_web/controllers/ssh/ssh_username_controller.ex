# edge_admin/lib/edge_admin_web/controllers/ssh/ssh_username_controller.ex
defmodule EdgeAdminWeb.Controllers.Ssh.SshUsernameController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Ssh
  alias EdgeAdmin.Ssh.Schemas.SshUsername
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.PathParams
  alias EdgeAdminWeb.Schemas.QueryParams
  alias EdgeAdminWeb.Schemas.Ssh.SshUsernameSchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index, :show, :create, :delete]

  tags(["Ssh.SshUsername"])

  operation(:index,
    summary: "List SSH usernames",
    description: "Returns a paginated list of SSH usernames with filtering and sorting",
    parameters:
      QueryParams.pagination() ++
        QueryParams.sort(order_by_example: "inserted_at,username", order_directions_example: "desc,asc") ++
        [
          QueryParams.string_filter(:username,
            description: "Filter by username — exact match or wildcard (root*, *admin, *deploy*)"
          ),
          QueryParams.string_in_filter(:username,
            description: "Filter by username — comma-separated list for IN match (e.g. username__in=deploy,admin)"
          ),
          QueryParams.uuid_in_filter(:node_id,
            description: "Filter by node IDs — comma-separated list of UUIDs (e.g. node_id__in=uuid1,uuid2)"
          ),
          QueryParams.boolean_filter(:has_password, description: "Filter by whether username has password configured"),
          QueryParams.string_filter(:cluster_name,
            description: "Filter by cluster name via node's cluster — exact match or wildcard (prod*, *east, *rod*)"
          ),
          QueryParams.string_in_filter(:cluster_name,
            description:
              "Filter by cluster name — comma-separated list for IN match (e.g. cluster_name__in=prod,staging)"
          ),
          QueryParams.string_filter(:key_name,
            description: "Filter by associated public key name — exact match or wildcard (laptop*, *prod)"
          ),
          QueryParams.string_in_filter(:key_name,
            description:
              "Filter by associated public key name — comma-separated list for IN match (e.g. key_name__in=laptop,server-key). Returns usernames that have at least one matching key."
          )
        ] ++
        QueryParams.datetime_range_filter(:inserted_at) ++
        QueryParams.datetime_range_filter(:updated_at),
    responses: %{
      200 => {"Paginated list of SSH usernames", "application/json", SshUsernameSchemas.SshUsernamePaginatedResponse},
      400 => {"Invalid query parameters", "application/json", CommonSchemas.BadRequestResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {ssh_usernames, meta}} <- Ssh.list_ssh_usernames(params) do
      render(conn, :index, conn: conn, ssh_usernames: ssh_usernames, meta: meta)
    end
  end

  operation(:create,
    summary: "Create SSH username",
    description: "Create a new SSH username for a specific node, optionally with public keys and/or password",
    parameters: [PathParams.uuid(:node_id, "Node ID to create SSH username for")],
    request_body:
      {"SSH username creation data", "application/json", SshUsernameSchemas.SshUsernameCreateRequest, required: true},
    responses: %{
      201 => {"SSH username created", "application/json", SshUsernameSchemas.SshUsernameSingleResponse},
      404 => {"Node not found", "application/json", CommonSchemas.NotFoundResponse},
      409 => {"Username already exists for this node", "application/json", CommonSchemas.ConflictResponse},
      422 => {"Validation error", "application/json", CommonSchemas.ChangesetErrorResponse}
    }
  )

  def create(conn, %{node_id: node_id} = params) do
    with {:ok, node} <- Nodes.get_node(node_id),
         {:ok, %SshUsername{} = ssh_username} <-
           Ssh.create_ssh_username_with_keys(node, Map.merge(params, conn.body_params)) do
      # Ensure keys are loaded for response
      ssh_username = EdgeAdmin.Repo.preload(ssh_username, :ssh_public_keys)

      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/ssh_usernames/#{ssh_username}")
      |> render(:show, conn: conn, ssh_username: ssh_username)
    end
  end

  operation(:show,
    summary: "Get SSH username",
    description: "Get a specific SSH username by ID",
    parameters: [PathParams.uuid(:id, "SSH username ID")],
    responses: %{
      200 => {"SSH username details", "application/json", SshUsernameSchemas.SshUsernameSingleResponse},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"SSH username not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{id: id}) do
    with {:ok, ssh_username} <- Ssh.get_ssh_username(id) do
      render(conn, :show, conn: conn, ssh_username: ssh_username)
    end
  end

  operation(:delete,
    summary: "Delete SSH username",
    description: "Delete an SSH username and all associated public keys",
    parameters: [PathParams.uuid(:id, "SSH username ID")],
    responses: %{
      204 => {"SSH username deleted", "", nil},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"SSH username not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def delete(conn, %{id: id}) do
    with {:ok, ssh_username} <- Ssh.get_ssh_username(id),
         {:ok, %SshUsername{}} <- Ssh.delete_ssh_username(ssh_username) do
      send_resp(conn, :no_content, "")
    end
  end
end
