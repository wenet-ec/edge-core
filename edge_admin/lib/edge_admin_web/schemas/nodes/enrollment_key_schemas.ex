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
        token: %Schema{
          type: :string,
          description: "The enrollment token used by netclient to join the network",
          example: "eyJzZXJ2ZXIiOiIxMC4wLjAuMSIsInZhbHVlIjoiQUJDMTIzIn0="
        },
        key_type: %Schema{
          type: :string,
          description: "Key type: 'default' (Netmaker default, unlimited) or 'custom' (user-specified limits)",
          enum: ["default", "custom"],
          example: "default"
        }
      },
      required: [:token, :key_type],
      example: %{
        token: "eyJzZXJ2ZXIiOiIxMC4wLjAuMSIsInZhbHVlIjoiQUJDMTIzIn0=",
        key_type: "default"
      }
    })
  end

  defmodule EnrollmentKeyResponse do
    @moduledoc false

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
          token: "eyJzZXJ2ZXIiOiIxMC4wLjAuMSIsInZhbHVlIjoiQUJDMTIzIn0=",
          key_type: "default"
        }
      }
    })
  end

  defmodule EnrollmentKeyCreateRequest do
    @moduledoc false

    OpenApiSpex.schema(%{
      title: "Enrollment Key Request",
      description: """
      Parameters for creating or retrieving an enrollment key.

      **Default**: Retrieves the Netmaker auto-generated default key (unlimited uses, no expiration).

      **Custom**: Creates a new key with user-specified expiry and uses (not tracked in DB, tagged for audit).
      """,
      type: :object,
      properties: %{
        enrollment_key: %Schema{
          type: :object,
          properties: %{
            key_type: %Schema{
              type: :string,
              nullable: true,
              description:
                "Key type: 'default' (retrieves default key) or 'custom' (user-specified limits). Default: 'default'",
              enum: ["default", "custom"],
              example: "default"
            },
            expiration: %Schema{
              type: :integer,
              nullable: true,
              description: "Expiration time in seconds (only for custom). Default: 3600 (1 hour)",
              example: 3600
            },
            uses_remaining: %Schema{
              type: :integer,
              nullable: true,
              description: "Number of allowed uses (only for custom). Default: 1",
              example: 1
            }
          },
          example: %{
            key_type: "custom",
            expiration: 3600,
            uses_remaining: 1
          }
        }
      },
      example: %{
        enrollment_key: %{
          key_type: "custom",
          expiration: 3600,
          uses_remaining: 1
        }
      }
    })
  end
end
