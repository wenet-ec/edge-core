# edge_admin_web/lib/edge_admin_web/schemas/nodes/enrollment_key_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.EnrollmentKeySchemas do
  @moduledoc """
  OpenAPI schemas for EnrollmentKey resources
  """

  alias OpenApiSpex.Schema

  defmodule EnrollmentKeyData do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "EnrollmentKey",
      description: "Enrollment key information",
      type: :object,
      properties: %{
        key_value: %Schema{
          type: :string,
          description: "The actual enrollment key value from Netmaker",
          example: "nmkey-abc123def456"
        },
        key_type: %Schema{
          type: :string,
          description:
            "Key type: 'permanent' (production nodes, not tracked) or 'ephemeral' (temp access, auto-cleanup)",
          enum: ["permanent", "ephemeral"],
          example: "permanent"
        },
        tracked: %Schema{
          type: :boolean,
          description: "Whether this key is tracked in DB for cleanup (true for ephemeral, false for permanent)",
          example: false
        }
      },
      required: [:key_value, :key_type, :tracked],
      example: %{
        key_value: "nmkey-abc123def456",
        key_type: "permanent",
        tracked: false
      }
    })
  end

  defmodule EnrollmentKeyResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Enrollment Key Response",
      description: "Single enrollment key response",
      type: :object,
      properties: %{
        data: EnrollmentKeyData
      },
      required: [:data],
      example: %{
        data: %{
          key_value: "nmkey-abc123def456",
          key_type: "permanent",
          tracked: false
        }
      }
    })
  end

  defmodule EnrollmentKeyCreateRequest do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Enrollment Key Create Request",
      description:
        "Parameters for creating an enrollment key. Use 'permanent' (default) for production nodes, 'ephemeral' for temporary access.",
      type: :object,
      properties: %{
        enrollment_key: %Schema{
          type: :object,
          properties: %{
            key_type: %Schema{
              type: :string,
              nullable: true,
              description:
                "Key type: 'permanent' (not tracked, for production) or 'ephemeral' (tracked, auto-cleanup). Default: 'permanent'",
              enum: ["permanent", "ephemeral"],
              example: "permanent"
            },
            expiry: %Schema{
              type: :integer,
              nullable: true,
              description: "Key expiration time in seconds (default: 86400 = 24 hours)",
              example: 86400
            },
            uses: %Schema{
              type: :integer,
              nullable: true,
              description: "Number of times the key can be used (default: 1)",
              example: 1
            }
          },
          example: %{
            key_type: "permanent",
            expiry: 86400,
            uses: 1
          }
        }
      },
      example: %{
        enrollment_key: %{
          key_type: "permanent",
          expiry: 86400,
          uses: 1
        }
      }
    })
  end
end
