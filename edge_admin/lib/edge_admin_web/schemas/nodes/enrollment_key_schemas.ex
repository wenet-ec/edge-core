# edge_admin_web/lib/edge_admin_web/schemas/nodes/enrollment_key_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.EnrollmentKeySchemas do
  @moduledoc """
  OpenAPI schemas for EnrollmentKey resources
  """

  use EdgeAdminWeb.Schema

  alias OpenApiSpex.Schema

  defmodule EnrollmentKeyData do
    @moduledoc false

    schema(%{
      title: "EnrollmentKeyResponse",
      description: "Enrollment key information",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, description: "Enrollment key ID"},
        cluster_name: %Schema{type: :string, description: "Cluster this key belongs to"},
        key: %Schema{
          type: :string,
          description: "Enrollment key blob (base64 JSON). Set as ENROLLMENT_KEY on the agent."
        },
        uses_remaining: %Schema{
          type: :integer,
          description: "Remaining uses. -1 means unlimited."
        },
        expired_at: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "Expiry datetime (ISO 8601). null means never expires."
        },
        last_used_at: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "When the key was last used. null if unused."
        },
        inserted_at: %Schema{type: :string, format: :"date-time", description: "When the enrollment key was created"},
        updated_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the enrollment key was last updated"
        }
      },
      required: [:id, :cluster_name, :key, :uses_remaining, :inserted_at, :updated_at]
    })
  end

  defmodule EnrollmentKeySingleResponse do
    @moduledoc false

    schema(%{
      title: "EnrollmentKeySingleResponse",
      description: "Single enrollment key response",
      type: :object,
      properties: %{data: EnrollmentKeyData},
      required: [:data]
    })
  end

  defmodule EnrollmentKeyPaginatedResponse do
    @moduledoc false

    schema(
      EdgeAdminWeb.Schemas.CommonSchemas.paginated_response(
        EnrollmentKeyData,
        "EnrollmentKeyPaginatedResponse",
        "Paginated list of enrollment keys with filtering and sorting metadata"
      )
    )
  end

  defmodule EnrollmentKeyCreateRequest do
    @moduledoc false

    schema(%{
      title: "EnrollmentKeyCreateRequest",
      description: "Parameters for creating a new enrollment key for a cluster",
      type: :object,
      properties: %{
        enrollment_key: %Schema{
          type: :object,
          properties: %{
            uses_remaining: %Schema{
              type: :integer,
              nullable: true,
              description: "Number of uses. -1 for unlimited. Defaults to 1."
            },
            expired_at: %Schema{
              type: :string,
              format: :"date-time",
              nullable: true,
              description: "Expiry datetime (ISO 8601). Omit for no expiry.",
              example: "2026-12-31T23:59:59Z"
            }
          }
        }
      },
      example: %{enrollment_key: %{uses_remaining: 1, expired_at: "2026-12-31T23:59:59Z"}}
    })
  end

  defmodule EnrollmentKeyUpdateRequest do
    @moduledoc false

    schema(%{
      title: "EnrollmentKeyUpdateRequest",
      description:
        "Parameters for updating an enrollment key. Only provided fields are updated. Pass null to unset a nullable field.",
      type: :object,
      properties: %{
        enrollment_key: %Schema{
          type: :object,
          properties: %{
            uses_remaining: %Schema{
              type: :integer,
              nullable: true,
              description: "Number of uses. -1 for unlimited."
            },
            expired_at: %Schema{
              type: :string,
              format: :"date-time",
              nullable: true,
              description: "Expiry datetime (ISO 8601). Pass null to remove expiry.",
              example: "2026-12-31T23:59:59Z"
            }
          }
        }
      },
      example: %{enrollment_key: %{expired_at: "2026-12-31T23:59:59Z"}}
    })
  end
end
