# edge_admin/lib/edge_admin_web/schemas/agents/enrollment_key_schemas.ex
defmodule EdgeAdminWeb.Schemas.Agents.EnrollmentKeySchemas do
  @moduledoc """
  OpenAPI schemas for agent enrollment key verification endpoints.
  """

  use EdgeAdminWeb.Schema

  alias OpenApiSpex.Schema

  defmodule EnrollmentKeyVerifyResponse do
    @moduledoc false

    schema(%{
      title: "Internal.EnrollmentKeyVerifyResponse",
      description: "Result of enrollment key verification. Always returns 200 — check `verified` field.",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            verified: %Schema{
              type: :boolean,
              description: "Whether the enrollment key is valid and unused"
            },
            error: %Schema{
              type: :string,
              description: "Error message if verification failed, empty string otherwise"
            },
            netmaker_key: %Schema{
              type: :string,
              description: "Netmaker enrollment key to use for VPN join, empty string if not verified"
            }
          },
          required: [:verified, :error, :netmaker_key]
        }
      },
      required: [:data],
      example: %{
        data: %{
          verified: true,
          error: "",
          netmaker_key: "eyJhbGciOiJIUzI1NiJ9..."
        }
      }
    })
  end
end
