# edge_admin_web/lib/edge_admin_web/schemas/nodes/enrollment_key_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.EnrollmentKeySchemas do
  @moduledoc """
  OpenAPI schemas for EnrollmentKey resources
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  defmodule EnrollmentKeyData do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "EnrollmentKey",
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
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :cluster_name, :key, :uses_remaining, :inserted_at, :updated_at]
    })
  end

  defmodule EnrollmentKeySingleResponse do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "EnrollmentKeySingleResponse",
      type: :object,
      properties: %{data: EnrollmentKeyData},
      required: [:data]
    })
  end

  defmodule EnrollmentKeyPaginatedResponse do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "EnrollmentKeyPaginatedResponse",
      type: :object,
      properties: %{
        data: %Schema{type: :array, items: EnrollmentKeyData},
        pagination: %Schema{
          type: :object,
          properties: %{
            page: %Schema{type: :integer},
            page_size: %Schema{type: :integer},
            total: %Schema{type: :integer},
            total_pages: %Schema{type: :integer},
            has_next: %Schema{type: :boolean},
            has_prev: %Schema{type: :boolean}
          }
        }
      },
      required: [:data, :pagination]
    })
  end

  defmodule EnrollmentKeyCreateRequest do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "EnrollmentKeyCreateRequest",
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

    OpenApiSpex.schema(%{
      title: "EnrollmentKeyUpdateRequest",
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
