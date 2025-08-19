# edge_admin/lib/edge_admin_web/controllers/nodes/ssh_public_key_controller.ex
defmodule EdgeAdminWeb.Nodes.SshPublicKeyController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.SshPublicKey
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.SshPublicKeySchemas

  action_fallback(EdgeAdminWeb.FallbackController)

  tags(["Nodes.SshPublicKey"])

  operation(:index,
    summary: "List SSH public keys",
    description: "Returns a paginated list of SSH public keys with filtering and sorting",
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
      key_name: [
        in: :query,
        description: "Filter by key name (supports wildcards with *)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      ssh_username_id: [
        in: :query,
        description: "Filter by SSH username ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 =>
        {"Paginated list of SSH public keys", "application/json", SshPublicKeySchemas.SshPublicKeyPaginatedResponse}
    }
  )

  def index(conn, params) do
    page_result = Nodes.list_ssh_public_keys_with_filtering_pagination(params)
    render(conn, :index, page_result: page_result)
  end

  operation(:create,
    summary: "Create SSH public key",
    description: """
    Create a new SSH public key for a specific SSH username.
    """,
    parameters: [
      ssh_username_id: [
        in: :path,
        description: "SSH username ID to create public key for",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    request_body: {"SSH public key creation data", "application/json", SshPublicKeySchemas.SshPublicKeyCreateRequest},
    responses: %{
      201 => {"SSH public key created", "application/json", SshPublicKeySchemas.SshPublicKeySingleResponse},
      422 =>
        {"Validation error - Invalid key format, unsupported algorithm, or duplicate key name", "application/json",
         CommonSchemas.ErrorResponse},
      404 => {"SSH username not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def create(conn, %{"ssh_username_id" => ssh_username_id, "ssh_public_key" => ssh_public_key_params}) do
    ssh_public_key_params = Map.put(ssh_public_key_params, "ssh_username_id", ssh_username_id)

    with {:ok, %SshPublicKey{} = ssh_public_key} <-
           Nodes.create_ssh_public_key(ssh_public_key_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/ssh_public_keys/#{ssh_public_key}")
      |> render(:show, ssh_public_key: ssh_public_key)
    end
  end

  operation(:show,
    summary: "Get SSH public key",
    description: "Get a specific SSH public key by ID",
    parameters: [
      id: [
        in: :path,
        description: "SSH public key ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"SSH public key details", "application/json", SshPublicKeySchemas.SshPublicKeySingleResponse},
      404 => {"SSH public key not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{"id" => id}) do
    ssh_public_key = Nodes.get_ssh_public_key!(id)
    render(conn, :show, ssh_public_key: ssh_public_key)
  end

  operation(:delete,
    summary: "Delete SSH public key",
    description: "Delete a SSH public key",
    parameters: [
      id: [
        in: :path,
        description: "SSH public key ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      204 => {"SSH public key deleted", "application/json", nil},
      404 => {"SSH public key not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def delete(conn, %{"id" => id}) do
    ssh_public_key = Nodes.get_ssh_public_key!(id)

    with {:ok, %SshPublicKey{}} <- Nodes.delete_ssh_public_key(ssh_public_key) do
      send_resp(conn, :no_content, "")
    end
  end
end
