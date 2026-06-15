# edge_admin/lib/edge_admin_web/controllers/ssh/ssh_public_key_controller.ex
defmodule EdgeAdminWeb.Controllers.Ssh.SshPublicKeyController do
  use EdgeAdminWeb, :api_controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Ssh
  alias EdgeAdmin.Ssh.Schemas.SshPublicKey
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.PathParams
  alias EdgeAdminWeb.Schemas.QueryParams
  alias EdgeAdminWeb.Schemas.Ssh.SshPublicKeySchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index, :show, :create, :delete]

  tags(["Ssh.SshPublicKey"])

  operation(:index,
    summary: "List SSH public keys",
    description: "Returns a paginated list of SSH public keys with filtering and sorting",
    parameters:
      QueryParams.pagination() ++
        QueryParams.sort(order_by_example: "inserted_at,key_name", order_directions_example: "desc,asc") ++
        [
          QueryParams.string_filter(:key_name,
            description: "Filter by key name (exact match or wildcard: my-key*, *prod, etc.)"
          ),
          QueryParams.string_filter(:public_key,
            description: "Filter by public key content (useful for searching email comments: *@example.com)"
          ),
          QueryParams.uuid_array_filter(:ssh_username_ids,
            description: "Filter by SSH username IDs — comma-separated list of UUIDs (exact IN match)"
          ),
          QueryParams.uuid_array_filter(:node_ids,
            description: "Filter by node IDs — comma-separated list of UUIDs (exact IN match)"
          ),
          QueryParams.string_filter(:username,
            description:
              "Filter by SSH username — exact match or wildcard (deploy*, *admin, etc.). Use usernames for multi-username IN matching."
          ),
          QueryParams.string_array_filter(:usernames,
            description:
              "Filter by SSH usernames — comma-separated list for exact IN match (e.g. deploy,admin). No wildcards; use username for wildcard filtering."
          ),
          QueryParams.string_filter(:cluster_name,
            description:
              "Filter by cluster name via node's cluster — exact match or wildcard (prod*, *east, *rod*). Use cluster_names for multi-cluster IN matching."
          ),
          QueryParams.string_array_filter(:cluster_names,
            description:
              "Filter by cluster names — comma-separated list for exact IN match (e.g. prod,staging). No wildcards; use cluster_name for wildcard filtering."
          )
        ] ++
        QueryParams.datetime_range_filter(:inserted_at) ++
        QueryParams.datetime_range_filter(:updated_at),
    responses: %{
      200 =>
        {"Paginated list of SSH public keys", "application/json", SshPublicKeySchemas.SshPublicKeyPaginatedResponse},
      400 => {"Invalid query parameters", "application/json", CommonSchemas.BadRequestResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {ssh_public_keys, meta}} <- Ssh.list_ssh_public_keys(params) do
      render(conn, :index, conn: conn, ssh_public_keys: ssh_public_keys, meta: meta)
    end
  end

  operation(:create,
    summary: "Create SSH public key",
    description: "Create a new SSH public key for a specific SSH username. The key must be in valid OpenSSH format.",
    parameters: [PathParams.uuid(:ssh_username_id, "SSH username ID to create public key for")],
    request_body:
      {"SSH public key creation data", "application/json", SshPublicKeySchemas.SshPublicKeyCreateRequest,
       required: true},
    responses: %{
      201 => {"SSH public key created", "application/json", SshPublicKeySchemas.SshPublicKeySingleResponse},
      404 => {"SSH username not found", "application/json", CommonSchemas.NotFoundResponse},
      409 => {"Key name already exists for this username", "application/json", CommonSchemas.ConflictResponse},
      422 =>
        {"Validation error - invalid key format or unsupported algorithm", "application/json",
         CommonSchemas.ChangesetErrorResponse}
    }
  )

  def create(conn, %{ssh_username_id: ssh_username_id} = params) do
    with {:ok, ssh_username} <- Ssh.get_ssh_username(ssh_username_id),
         {:ok, %SshPublicKey{} = ssh_public_key} <-
           Ssh.create_ssh_public_key(ssh_username, Map.merge(params, conn.body_params)) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/v1/ssh_public_keys/#{ssh_public_key}")
      |> render(:show, conn: conn, ssh_public_key: ssh_public_key)
    end
  end

  operation(:show,
    summary: "Get SSH public key",
    description: "Get a specific SSH public key by ID",
    parameters: [PathParams.uuid(:id, "SSH public key ID")],
    responses: %{
      200 => {"SSH public key details", "application/json", SshPublicKeySchemas.SshPublicKeySingleResponse},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"SSH public key not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{id: id}) do
    with {:ok, ssh_public_key} <- Ssh.get_ssh_public_key(id) do
      render(conn, :show, conn: conn, ssh_public_key: ssh_public_key)
    end
  end

  operation(:delete,
    summary: "Delete SSH public key",
    description: "Delete an SSH public key",
    parameters: [PathParams.uuid(:id, "SSH public key ID")],
    responses: %{
      204 => {"SSH public key deleted", "", nil},
      400 => {"Invalid path parameters", "application/json", CommonSchemas.BadRequestResponse},
      404 => {"SSH public key not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def delete(conn, %{id: id}) do
    with {:ok, ssh_public_key} <- Ssh.get_ssh_public_key(id),
         {:ok, %SshPublicKey{}} <- Ssh.delete_ssh_public_key(ssh_public_key) do
      send_resp(conn, :no_content, "")
    end
  end
end
