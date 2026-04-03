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
          nullable: true,
          description: "Remaining uses. null means unlimited."
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
      description: "Parameters for creating a new enrollment key for a cluster. All fields are optional.",
      type: :object,
      properties: %{
        enrollment_key: %Schema{
          type: :object,
          properties: %{
            uses_remaining: %Schema{
              type: :integer,
              nullable: true,
              minimum: 1,
              description: "Number of uses (must be >= 1). Pass null for unlimited. Omit to use the default of 1.",
              example: 5
            },
            expired_at: %Schema{
              type: :string,
              format: :"date-time",
              nullable: true,
              description: "Expiry datetime (ISO 8601). Omit or pass null for no expiry.",
              example: "2026-12-31T23:59:59Z"
            }
          }
        }
      },
      example: %{enrollment_key: %{uses_remaining: 5, expired_at: "2026-12-31T23:59:59Z"}}
    })
  end

  defmodule EnrollmentKeyUpdateRequest do
    @moduledoc false

    schema(%{
      title: "EnrollmentKeyUpdateRequest",
      description: """
      Parameters for updating an enrollment key. Only fields that are present in the request body are updated — omitting a field leaves it unchanged.

      - `uses_remaining`: pass a positive integer to set a limit, or `null` to make the key unlimited.
      - `expired_at`: pass a datetime to set expiry, or `null` to remove expiry.
      """,
      type: :object,
      properties: %{
        enrollment_key: %Schema{
          type: :object,
          properties: %{
            uses_remaining: %Schema{
              type: :integer,
              nullable: true,
              minimum: 1,
              description:
                "Positive integer to set a use limit, or null to make the key unlimited. Omit to leave unchanged.",
              example: 10
            },
            expired_at: %Schema{
              type: :string,
              format: :"date-time",
              nullable: true,
              description: "Expiry datetime (ISO 8601), or null to remove expiry. Omit to leave unchanged.",
              example: "2026-12-31T23:59:59Z"
            }
          }
        }
      },
      example: %{enrollment_key: %{uses_remaining: nil, expired_at: "2026-12-31T23:59:59Z"}}
    })
  end
end
