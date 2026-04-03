# edge_admin/lib/edge_admin_web/controllers/ssh/ssh_public_key_controller.ex
defmodule EdgeAdminWeb.Controllers.Ssh.SshPublicKeyController do
  use EdgeAdminWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EdgeAdmin.Ssh
  alias EdgeAdmin.Ssh.Schemas.SshPublicKey
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Ssh.SshPublicKeySchemas

  action_fallback(EdgeAdminWeb.Controllers.FallbackController)

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true
  plug EdgeAdminWeb.Plugs.DegradedMode, :allow when action in [:index, :show, :create, :delete]

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
        description: "Comma-separated list of sort directions (asc/desc) corresponding to order_by fields",
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
        description: "Filter by public key content (useful for searching email comments: *@example.com)",
        schema: %OpenApiSpex.Schema{type: :string}
      ],
      ssh_username_id: [
        in: :query,
        description: "Filter by SSH username ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ],
      inserted_at__gte: [
        in: :query,
        description:
          "Filter SSH public keys inserted after this datetime (e.g. 2025-01-01T00:00:00Z; date-only 2025-01-01 is treated as start of day UTC)",
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
          "Filter SSH public keys inserted before this datetime (e.g. 2025-01-01T23:59:59Z; date-only 2025-01-01 is treated as end of day UTC)",
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
          "Filter SSH public keys updated after this datetime (e.g. 2025-01-01T00:00:00Z; date-only 2025-01-01 is treated as start of day UTC)",
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
          "Filter SSH public keys updated before this datetime (e.g. 2025-01-01T23:59:59Z; date-only 2025-01-01 is treated as end of day UTC)",
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
        {"Paginated list of SSH public keys", "application/json", SshPublicKeySchemas.SshPublicKeyPaginatedResponse},
      422 => {"Invalid query parameters", "application/json", OpenApiSpex.JsonErrorResponse}
    }
  )

  def index(conn, params) do
    with {:ok, {ssh_public_keys, meta}} <- Ssh.list_ssh_public_keys(params) do
      render(conn, :index, ssh_public_keys: ssh_public_keys, meta: meta)
    end
  end

  operation(:create,
    summary: "Create SSH public key",
    description: "Create a new SSH public key for a specific SSH username. The key must be in valid OpenSSH format.",
    parameters: [
      ssh_username_id: [
        in: :path,
        description: "SSH username ID to create public key for",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
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
      404 => {"SSH public key not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Invalid path parameters", "application/json", OpenApiSpex.JsonErrorResponse}
    }
  )

  def show(conn, %{id: id}) do
    with {:ok, ssh_public_key} <- Ssh.get_ssh_public_key(id) do
      render(conn, :show, ssh_public_key: ssh_public_key)
    end
  end

  operation(:delete,
    summary: "Delete SSH public key",
    description: "Delete an SSH public key",
    parameters: [
      id: [
        in: :path,
        description: "SSH public key ID",
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      204 => {"SSH public key deleted", "", nil},
      404 => {"SSH public key not found", "application/json", CommonSchemas.NotFoundResponse},
      422 => {"Invalid path parameters", "application/json", OpenApiSpex.JsonErrorResponse}
    }
  )

  def delete(conn, %{id: id}) do
    with {:ok, ssh_public_key} <- Ssh.get_ssh_public_key(id),
         {:ok, %SshPublicKey{}} <- Ssh.delete_ssh_public_key(ssh_public_key) do
      send_resp(conn, :no_content, "")
    end
  end
end
