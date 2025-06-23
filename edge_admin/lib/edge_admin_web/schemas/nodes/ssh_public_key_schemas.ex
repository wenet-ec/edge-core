# edge_admin/lib/edge_admin_web/schemas/nodes/ssh_public_key_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.SshPublicKeySchemas do
  @moduledoc """
  OpenAPI schemas for SSH Public Key resources
  """

  alias OpenApiSpex.Schema
  alias EdgeAdminWeb.Schemas.CommonSchemas

  defmodule SshPublicKeyResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SSH Public Key",
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
          description: "SSH public key content",
          example: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ..."
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
          format: :datetime,
          description: "When the SSH public key was created"
        },
        updated_at: %Schema{
          type: :string,
          format: :datetime,
          description: "When the SSH public key was last updated"
        }
      },
      required: [:id, :public_key, :key_name, :ssh_username_id, :inserted_at, :updated_at],
      example: %{
        id: "01234567-89ab-cdef-0123-456789abcdef",
        public_key: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...",
        key_name: "laptop-key",
        ssh_username_id: "fedcba98-7654-3210-fedc-ba9876543210",
        inserted_at: "2025-06-23T10:30:00Z",
        updated_at: "2025-06-23T10:30:00Z"
      }
    })
  end

  defmodule SshPublicKeyPaginatedResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(
      CommonSchemas.paginated_response(
        SshPublicKeyResponse,
        "SSH Public Key Paginated Response",
        "Paginated list of SSH public keys with filtering and sorting metadata"
      )
    )
  end

  defmodule SshPublicKeySingleResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SSH Public Key Single Response",
      description: "Single SSH public key response",
      type: :object,
      properties: %{
        data: SshPublicKeyResponse
      },
      required: [:data],
      example: %{
        data: %{
          id: "01234567-89ab-cdef-0123-456789abcdef",
          public_key: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...",
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
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SSH Public Key Create Request",
      description: "Create a new SSH public key for a username",
      type: :object,
      properties: %{
        ssh_public_key: %Schema{
          type: :object,
          properties: %{
            public_key: %Schema{
              type: :string,
              description: "SSH public key content",
              example: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ..."
            },
            key_name: %Schema{
              type: :string,
              description: "Human-readable name for the SSH key",
              example: "laptop-key"
            }
          },
          required: [:public_key, :key_name],
          example: %{
            public_key: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ...",
            key_name: "laptop-key"
          }
        }
      },
      required: [:ssh_public_key]
    })
  end
end
