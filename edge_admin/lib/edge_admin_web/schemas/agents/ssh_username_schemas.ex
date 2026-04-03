# edge_admin/lib/edge_admin_web/schemas/agents/ssh_username_schemas.ex
defmodule EdgeAdminWeb.Schemas.Agents.SshUsernameSchemas do
  @moduledoc """
  OpenAPI schemas for agent SSH credential verification endpoints.
  """

  use EdgeAdminWeb.Schema

  alias OpenApiSpex.Schema

  defmodule SshCredentialsVerifyResponse do
    @moduledoc false

    schema(%{
      title: "Internal.SshCredentialsVerifyResponse",
      description: "Result of SSH credential verification. Always returns 200 — check `verified` field.",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            verified: %Schema{
              type: :boolean,
              description:
                "Whether the credential is valid. Returns false for both unknown username and wrong credential."
            }
          },
          required: [:verified]
        }
      },
      required: [:data],
      example: %{
        data: %{
          verified: true
        }
      }
    })
  end
end
