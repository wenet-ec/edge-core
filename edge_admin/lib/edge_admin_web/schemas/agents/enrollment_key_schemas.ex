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
        verified: %Schema{type: :boolean, description: "Whether the enrollment key is valid and unused"},
        error: %Schema{type: :string, description: "Error message if verification failed, empty string otherwise"},
        netmaker_key: %Schema{
          type: :string,
          description: "Netmaker enrollment key to use for VPN join, empty string if not verified"
        }
      },
      required: [:verified, :error, :netmaker_key],
      example: %{verified: true, error: "", netmaker_key: "eyJhbGciOiJIUzI1NiJ9..."}
    })
  end

  defmodule EnrollmentKeyVerifyResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(
        EnrollmentKeyVerifyData,
        "Internal.EnrollmentKeyVerifyResponse",
        "Result of enrollment key verification. Always returns 200 — check `verified` field."
      )
    )
  end
end
