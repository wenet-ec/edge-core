# edge_admin/lib/edge_admin_web/schemas/nodes/enrollment_key_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.EnrollmentKeySchemas do
  @moduledoc """
  OpenAPI schemas for Enrollment Key resources
  """

  alias OpenApiSpex.Schema

  defmodule EnrollmentKeyResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Enrollment Key",
      description: "VPN enrollment key for edge nodes",
      type: :object,
      properties: %{
        key: %Schema{
          type: :string,
          description: "The enrollment key string that nodes use to join the VPN",
          example: "preauth-key-abc123def456ghi789"
        },
        expiration: %Schema{
          type: :string,
          format: :datetime,
          description: "When the enrollment key expires",
          example: "2024-06-10T15:30:00Z"
        },
        inserted_at: %Schema{
          type: :string,
          format: :datetime,
          description: "When the enrollment key was created",
          example: "2024-06-10T14:30:00Z"
        }
      },
      required: [:key, :expiration, :inserted_at],
      example: %{
        key: "preauth-key-abc123def456ghi789",
        expiration: "2024-06-10T15:30:00Z",
        inserted_at: "2024-06-10T14:30:00Z"
      }
    })
  end
end
