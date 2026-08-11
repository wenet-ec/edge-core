# edge_admin/lib/edge_admin_web/schemas/agents/enrollment_key_schemas.ex
defmodule EdgeAdminWeb.Schemas.Agents.EnrollmentKeySchemas do
  @moduledoc """
  OpenAPI schemas for agent enrollment key verification endpoints.
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule EnrollmentKeyVerifyRequest do
    @moduledoc false

    schema(%{
      title: "Internal.EnrollmentKeyVerifyRequest",
      description: "Enrollment key to verify before VPN join",
      type: :object,
      additionalProperties: true,
      properties: %{
        key: %Schema{type: :string, description: "Enrollment key blob"}
      },
      required: [:key]
    })
  end

  defmodule EnrollmentKeyVerifyData do
    @moduledoc false

    schema(%{
      title: "Internal.EnrollmentKeyVerifyData",
      description: "Result of enrollment key verification",
      type: :object,
      properties: %{
        error: %Schema{type: :string, description: "Error message if verification failed, empty string otherwise"},
        netmaker_key: %Schema{
          type: :string,
          description: "Edge VPN enrollment key to use for VPN join, empty string if not verified"
        },
        enrollment_key_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "Admin enrollment key ID when verification succeeds, otherwise null"
        }
      },
      required: [:error, :netmaker_key, :enrollment_key_id],
      example: %{
        error: "",
        netmaker_key: "eyJhbGciOiJIUzI1NiJ9...",
        enrollment_key_id: "0190f1e0-7b2a-7abc-8def-0123456789ab"
      }
    })
  end

  defmodule EnrollmentKeyVerifyResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(
        EnrollmentKeyVerifyData,
        "Internal.EnrollmentKeyVerifyResponse",
        "Result of enrollment key verification. A non-null `enrollment_key_id` indicates success."
      )
    )
  end
end
