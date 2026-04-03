# edge_admin/lib/edge_admin_web/schemas/agents/ssh_username_schemas.ex
defmodule EdgeAdminWeb.Schemas.Agents.SshUsernameSchemas do
  @moduledoc """
  OpenAPI schemas for agent SSH credential verification endpoints.
  """

  use EdgeAdminWeb.Schema

  alias OpenApiSpex.Schema

  defmodule SshCredentialsVerifyRequest do
    @moduledoc false

    schema(%{
      title: "Internal.SshCredentialsVerifyRequest",
      description: "SSH credentials to verify. Provide either password or public_key, not both.",
      type: :object,
      additionalProperties: true,
      properties: %{
        ssh_username: %Schema{
          type: :object,
          additionalProperties: true,
          properties: %{
            username: %Schema{type: :string, description: "SSH username"},
            password: %Schema{
              type: :string,
              nullable: true,
              description: "Password (mutually exclusive with public_key)"
            },
            public_key: %Schema{
              type: :string,
              nullable: true,
              description: "Public key (mutually exclusive with password)"
            }
          },
          required: [:username]
        }
      },
      required: [:ssh_username]
    })
  end

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
