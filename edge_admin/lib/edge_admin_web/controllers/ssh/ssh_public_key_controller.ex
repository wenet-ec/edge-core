# edge_admin/lib/edge_admin_web/controllers/ssh/ssh_public_key_controller.ex
defmodule EdgeAdminWeb.Controllers.Ssh.SshPublicKeyController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Ssh
  alias EdgeAdmin.Ssh.Schemas.SshPublicKey
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Ssh.SshPublicKeySchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  tags(["Ssh.SshPublicKey"])

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
      order_by: [
        in: :query,
        description: "Comma-separated list of fields to sort by",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "inserted_at,key_name"
      ],
      order_directions: [
        in: :query,
        description:
          "Comma-separated list of sort directions (asc/desc) corresponding to order_by fields",
        schema: %OpenApiSpex.Schema{type: :string},
        example: "desc,asc"
      ],
      key_name: [
        in: :query,
        description: "Filter by key name (exact match or wildcard: my-key*, *prod, etc.)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      public_key: [
        in: :query,
        description:
          "Filter by public key content (useful for searching email comments: *@example.com)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      ssh_username_id: [
        in: :query,
        description: "Filter by SSH username ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ],
      inserted_at__gte: [
        in: :query,
        description: "Filter SSH public keys inserted after or on this date",
        schema: %OpenApiSpex.Schema{type: :string, format: :date}
      ],
      inserted_at__lte: [
        in: :query,
        description: "Filter SSH public keys inserted before or on this date",
        schema: %OpenApiSpex.Schema{type: :string, format: :date}
      ]
    ],
    responses: %{
      200 =>
        {"Paginated list of SSH public keys", "application/json",
         SshPublicKeySchemas.SshPublicKeyPaginatedResponse}
    }
  )

  def index(conn, params) do
    {:ok, {ssh_public_keys, meta}} = Ssh.list_ssh_public_keys(params)
    render(conn, :index, ssh_public_keys: ssh_public_keys, meta: meta)
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
    request_body:
      {"SSH public key creation data", "application/json",
       SshPublicKeySchemas.SshPublicKeyCreateRequest},
    responses: %{
      201 =>
        {"SSH public key created", "application/json",
         SshPublicKeySchemas.SshPublicKeySingleResponse},
      422 =>
        {"Validation error - Invalid key format, unsupported algorithm, or duplicate key name",
         "application/json", CommonSchemas.ErrorResponse},
      404 => {"SSH username not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def create(conn, %{"ssh_username_id" => ssh_username_id} = params) do
    with {:ok, ssh_username} <- Ssh.get_ssh_username(ssh_username_id),
         {:ok, %SshPublicKey{} = ssh_public_key} <-
           Ssh.create_ssh_public_key(ssh_username, params) do
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
      200 =>
        {"SSH public key details", "application/json",
         SshPublicKeySchemas.SshPublicKeySingleResponse},
      404 => {"SSH public key not found", "application/json", CommonSchemas.NotFoundResponse}
    }
  )

  def show(conn, %{"id" => id}) do
    with {:ok, ssh_public_key} <- Ssh.get_ssh_public_key(id) do
      render(conn, :show, ssh_public_key: ssh_public_key)
    end
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
    with {:ok, ssh_public_key} <- Ssh.get_ssh_public_key(id),
         {:ok, %SshPublicKey{}} <- Ssh.delete_ssh_public_key(ssh_public_key) do
      send_resp(conn, :no_content, "")
    end
  end
end
