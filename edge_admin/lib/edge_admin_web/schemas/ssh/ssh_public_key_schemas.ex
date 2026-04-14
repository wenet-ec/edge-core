# edge_admin/lib/edge_admin_web/schemas/ssh/ssh_public_key_schemas.ex
defmodule EdgeAdminWeb.Schemas.Ssh.SshPublicKeySchemas do
  @moduledoc """
  OpenAPI schemas for SSH Public Key resources
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule SshPublicKeyResponse do
    @moduledoc false

    schema(%{
      title: "SshPublicKey",
      description: "SSH public key information for username access",
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          format: :uuid,
          description: "Unique SSH public key identifier"
        },
        public_key: %Schema{
          type: :string,
          description: "SSH public key in OpenSSH format (algorithm base64data [comment])",
          example: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 user@laptop"
        },
        key_name: %Schema{
          type: :string,
          description: "Human-readable name for the SSH key",
          example: "laptop-key"
        },
        ssh_username_id: %Schema{
          type: :string,
          format: :uuid,
          description: "SSH username this key belongs to"
        },
        inserted_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the SSH public key was created"
        },
        updated_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the SSH public key was last updated"
        }
      },
      required: [:id, :public_key, :key_name, :ssh_username_id, :inserted_at, :updated_at],
      example: %{
        id: "01234567-89ab-cdef-0123-456789abcdef",
        public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 user@laptop",
        key_name: "laptop-key",
        ssh_username_id: "fedcba98-7654-3210-fedc-ba9876543210",
        inserted_at: "2025-06-23T10:30:00Z",
        updated_at: "2025-06-23T10:30:00Z"
      }
    })
  end

  defmodule SshPublicKeyPaginatedResponse do
    @moduledoc false

    schema(
      CommonSchemas.paginated_response(
        SshPublicKeyResponse,
        "SshPublicKeyPaginatedResponse",
        "Paginated list of SSH public keys with filtering and sorting metadata"
      )
    )
  end

  defmodule SshPublicKeySingleResponse do
    @moduledoc false

    schema(%{
      title: "SshPublicKeySingleResponse",
      description: "Single SSH public key response",
      type: :object,
      properties: %{
        data: SshPublicKeyResponse
      },
      required: [:data],
      example: %{
        data: %{
          id: "01234567-89ab-cdef-0123-456789abcdef",
          public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 user@laptop",
          key_name: "laptop-key",
          ssh_username_id: "fedcba98-7654-3210-fedc-ba9876543210",
          inserted_at: "2025-06-23T10:30:00Z",
          updated_at: "2025-06-23T10:30:00Z"
        }
      }
    })
  end

  defmodule SshPublicKeyCreateRequest do
    @moduledoc false

    schema(%{
      title: "SshPublicKeyCreateRequest",
      description: "Create a new SSH public key for a username. The key must be in valid OpenSSH format.",
      type: :object,
      properties: %{
        public_key: %Schema{
          type: :string,
          description:
            "SSH public key in OpenSSH format (algorithm base64data [comment]). Supported algorithms: ssh-ed25519 (recommended), ecdsa-sha2-nistp256, ecdsa-sha2-nistp384, ecdsa-sha2-nistp521, ssh-rsa",
          example: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 user@laptop",
          pattern: "^(ssh-ed25519|ecdsa-sha2-nistp(?:256|384|521)|ssh-rsa)\\s+[A-Za-z0-9+\\/]+=*\\s*.*$"
        },
        key_name: %Schema{
          type: :string,
          description: "Human-readable name for the SSH key",
          example: "laptop-key",
          minLength: 1,
          maxLength: 255
        }
      },
      required: [:public_key, :key_name],
      example: %{
        public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQw7Di3fBr2oc2vbZN5YLz8YpJ8PQb5bXwQwe+QgYX8 user@laptop",
        key_name: "laptop-key"
      }
    })
  end
end
