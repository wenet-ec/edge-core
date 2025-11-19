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
        token: %Schema{
          type: :string,
          description: "The enrollment token used by netclient to join the network",
          example: "eyJzZXJ2ZXIiOiIxMC4wLjAuMSIsInZhbHVlIjoiQUJDMTIzIn0="
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
      required: [:token, :key_type, :tracked],
      example: %{
        token: "eyJzZXJ2ZXIiOiIxMC4wLjAuMSIsInZhbHVlIjoiQUJDMTIzIn0=",
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
          token: "eyJzZXJ2ZXIiOiIxMC4wLjAuMSIsInZhbHVlIjoiQUJDMTIzIn0=",
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
      title: "Enrollment Key Request",
      description: """
      Parameters for getting an enrollment key.

      **Permanent (default)**: Retrieves the Netmaker default key (unlimited uses, no expiration).

      **Ephemeral**: Creates a new single-use key (1 hour expiration, tracked for auto-cleanup).
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
                "Key type: 'permanent' (retrieves default key) or 'ephemeral' (creates single-use key). Default: 'permanent'",
              enum: ["permanent", "ephemeral"],
              example: "permanent"
            }
          },
          example: %{
            key_type: "permanent"
          }
        }
      },
      example: %{
        enrollment_key: %{
          key_type: "permanent"
        }
      }
    })
  end
end
