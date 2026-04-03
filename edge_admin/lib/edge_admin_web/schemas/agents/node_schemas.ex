# edge_admin/lib/edge_admin_web/schemas/agents/node_schemas.ex
defmodule EdgeAdminWeb.Schemas.Agents.NodeSchemas do
  @moduledoc """
  OpenAPI schemas for agent node registration endpoints.
  """

  use EdgeAdminWeb.Schema

  alias OpenApiSpex.Schema

  defmodule NodeRegistrationResponse do
    @moduledoc false

    schema(%{
      title: "Internal.NodeRegistrationResponse",
      description: "Response after successful agent node registration",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            node_id: %Schema{
              type: :string,
              format: :uuid,
              description: "Registered node UUID"
            },
            api_token: %Schema{
              type: :string,
              description: "Bearer token for subsequent authenticated agent requests"
            },
            proxy_password: %Schema{
              type: :string,
              description: "Password for proxy authentication"
            },
            admin_urls: %Schema{
              type: :array,
              items: %Schema{type: :string},
              description: "List of admin HTTP fallback URLs"
            },
            derp_map_url: %Schema{
              type: :string,
              nullable: true,
              description: "URL to fetch the DERP relay map"
            }
          },
          required: [:node_id, :api_token, :proxy_password, :admin_urls]
        }
      },
      required: [:data],
      example: %{
        data: %{
          node_id: "01234567-89ab-cdef-0123-456789abcdef",
          api_token: "eyJhbGciOiJIUzI1NiJ9...",
          proxy_password: "s3cr3tpassword",
          admin_urls: ["http://10.0.0.1:44000"],
          derp_map_url: "https://controlplane.tailscale.com/derpmap/default"
        }
      }
    })
  end

  defmodule NodeHealthCheckResponse do
    @moduledoc false

    schema(%{
      title: "Internal.NodeHealthCheckResponse",
      description: "Response after reporting node health check status",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string, format: :uuid, description: "Node UUID"},
            status: %Schema{
              type: :string,
              enum: ["healthy", "unhealthy"],
              description: "Current node health status"
            },
            last_seen_at: %Schema{
              type: :string,
              format: :"date-time",
              nullable: true,
              description: "Last time the node was seen"
            }
          },
          required: [:id, :status]
        }
      },
      required: [:data],
      example: %{
        data: %{
          id: "01234567-89ab-cdef-0123-456789abcdef",
          status: "healthy",
          last_seen_at: "2026-04-02T10:00:00Z"
        }
      }
    })
  end
end
