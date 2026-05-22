# edge_admin/lib/edge_admin_web/schemas/nodes/enrollment_key_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.EnrollmentKeySchemas do
  @moduledoc """
  OpenAPI schemas for EnrollmentKey resources
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
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
        name: %Schema{
          type: :string,
          nullable: true,
          description: "Optional human-readable label for this key (display only). null if unset."
        },
        key: %Schema{
          type: :string,
          description: "Enrollment key blob (base64 JSON). Set as ENROLLMENT_KEY on the agent."
        },
        uses_remaining: %Schema{
          type: :integer,
          nullable: true,
          description: "Remaining uses. null means unlimited."
        },
        expires_at: %Schema{
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
      required: [:id, :cluster_name, :key, :uses_remaining, :inserted_at, :updated_at],
      example: %{
        id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        cluster_name: "prod-east",
        name: "prod rollout",
        key: "eyJzZXJ2ZXIiOiJodHRwczovL25ldG1ha2VyLmV4YW1wbGUuY29tIiwia2V5IjoiYWJjMTIzIn0=",
        uses_remaining: 5,
        expires_at: "2026-12-31T23:59:59Z",
        last_used_at: nil,
        inserted_at: "2025-06-09T08:00:00Z",
        updated_at: "2025-06-09T08:00:00Z"
      }
    })
  end

  defmodule EnrollmentKeySingleResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(EnrollmentKeyData, "EnrollmentKeySingleResponse", "Single enrollment key response")
    )
  end

  defmodule EnrollmentKeyPaginatedResponse do
    @moduledoc false

    schema(
      CommonSchemas.paginated_response(
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
        name: %Schema{
          type: :string,
          nullable: true,
          description: "Optional human-readable label for this key. Display only — not used for lookup.",
          example: "prod rollout"
        },
        uses_remaining: %Schema{
          type: :integer,
          nullable: true,
          minimum: 1,
          description: "Number of uses (must be >= 1). Pass null for unlimited. Omit to use the default of 1.",
          example: 5
        },
        expires_at: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "Expiry datetime (ISO 8601). Omit or pass null for no expiry.",
          example: "2026-12-31T23:59:59Z"
        }
      },
      example: %{name: "prod rollout", uses_remaining: 5, expires_at: "2026-12-31T23:59:59Z"}
    })
  end

  defmodule EnrollmentKeyUpdateRequest do
    @moduledoc false

    schema(%{
      title: "EnrollmentKeyUpdateRequest",
      description: """
      Parameters for updating an enrollment key. Only fields that are present in the request body are updated — omitting a field leaves it unchanged.

      - `name`: pass a string to set a label, or `null` to clear it.
      - `uses_remaining`: pass a positive integer to set a limit, or `null` to make the key unlimited.
      - `expires_at`: pass a datetime to set expiry, or `null` to remove expiry.
      """,
      type: :object,
      properties: %{
        name: %Schema{
          type: :string,
          nullable: true,
          description: "Human-readable label for this key, or null to clear. Omit to leave unchanged.",
          example: "prod rollout"
        },
        uses_remaining: %Schema{
          type: :integer,
          nullable: true,
          minimum: 1,
          description:
            "Positive integer to set a use limit, or null to make the key unlimited. Omit to leave unchanged.",
          example: 10
        },
        expires_at: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "Expiry datetime (ISO 8601), or null to remove expiry. Omit to leave unchanged.",
          example: "2026-12-31T23:59:59Z"
        }
      },
      example: %{name: "prod rollout", uses_remaining: nil, expires_at: "2026-12-31T23:59:59Z"}
    })
  end
end
