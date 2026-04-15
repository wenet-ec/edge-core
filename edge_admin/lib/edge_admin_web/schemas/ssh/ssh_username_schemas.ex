# edge_admin/lib/edge_admin_web/schemas/ssh/ssh_username_schemas.ex
defmodule EdgeAdminWeb.Schemas.Ssh.SshUsernameSchemas do
  @moduledoc """
  OpenAPI schemas for SSH Username resources
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Ssh.SshPublicKeySchemas
  alias OpenApiSpex.Schema

  defmodule SshUsernameResponse do
    @moduledoc false

    schema(%{
      title: "SshUsername",
      description: "SSH username information for node access",
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          format: :uuid,
          description: "Unique SSH username identifier"
        },
        username: %Schema{
          type: :string,
          description: "SSH username for node access (3-32 characters)",
          example: "admin"
        },
        has_password: %Schema{
          type: :boolean,
          description: "Whether this username has a password configured for authentication",
          example: true
        },
        node_id: %Schema{
          type: :string,
          format: :uuid,
          description: "Node this username belongs to"
        },
        public_keys: %Schema{
          type: :array,
          description: "SSH public keys associated with this username (only included when preloaded)",
          items: SshPublicKeySchemas.SshPublicKeyResponse,
          nullable: true
        },
        inserted_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the SSH username was created"
        },
        updated_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the SSH username was last updated"
        }
      },
      required: [:id, :username, :has_password, :node_id, :inserted_at, :updated_at],
      example: %{
        id: "01234567-89ab-cdef-0123-456789abcdef",
        username: "admin",
        has_password: true,
        node_id: "fedcba98-7654-3210-fedc-ba9876543210",
        public_keys: [
          %{
            id: "fedcba98-7654-3210-fedc-ba9876543210",
            key_name: "laptop",
            public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 user@laptop",
            ssh_username_id: "01234567-89ab-cdef-0123-456789abcdef",
            inserted_at: "2025-06-23T10:30:00Z",
            updated_at: "2025-06-23T10:30:00Z"
          }
        ],
        inserted_at: "2025-06-23T10:30:00Z",
        updated_at: "2025-06-23T10:30:00Z"
      }
    })
  end

  defmodule SshUsernamePaginatedResponse do
    @moduledoc false

    schema(
      CommonSchemas.paginated_response(
        SshUsernameResponse,
        "SshUsernamePaginatedResponse",
        "Paginated list of SSH usernames with filtering and sorting metadata"
      )
    )
  end

  defmodule SshUsernameSingleResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(
        SshUsernameResponse,
        "SshUsernameSingleResponse",
        "Single SSH username response"
      )
    )
  end

  defmodule SshUsernameCreateRequest do
    @moduledoc false

    schema(%{
      title: "SshUsernameCreateRequest",
      description: "Create a new SSH username for a node, optionally with password and/or public keys",
      type: :object,
      properties: %{
        username: %Schema{
          type: :string,
          description:
            "SSH username for node access (3-32 characters, must start with letter or underscore, lowercase letters/digits/hyphens/underscores only)",
          example: "admin",
          pattern: "^[a-z_][a-z0-9_-]*$",
          minLength: 3,
          maxLength: 32
        },
        password: %Schema{
          type: :string,
          description:
            "Optional password for username/password SSH authentication (12-128 characters if provided, will be hashed with Argon2)",
          example: "MySecurePassword123!",
          minLength: 12,
          maxLength: 128,
          nullable: true
        },
        public_keys: %Schema{
          type: :array,
          description: "Optional array of SSH public keys to create with this username",
          items: %Schema{
            type: :object,
            properties: %{
              key_name: %Schema{
                type: :string,
                description: "Human-readable name for the SSH key",
                example: "laptop"
              },
              public_key: %Schema{
                type: :string,
                description: "SSH public key in OpenSSH format",
                example: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 user@laptop"
              }
            },
            required: [:key_name, :public_key]
          },
          nullable: true
        }
      },
      required: [:username],
      example: %{
        username: "admin",
        password: "MySecurePassword123!",
        public_keys: [
          %{
            key_name: "laptop",
            public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 user@laptop"
          },
          %{key_name: "ci", public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... ci@deploy"}
        ]
      }
    })
  end
end
