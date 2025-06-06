# edge_admin/lib/edge_admin_web/schemas/vpn/connection_schemas.ex
defmodule EdgeAdminWeb.Schemas.VPN.ConnectionSchemas do
  @moduledoc """
  OpenAPI schemas for VPN connection resources.
  """

  alias OpenApiSpex.Schema

  defmodule ConnectionResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "VPN Connection",
      description: "VPN connection status and details",
      type: :object,
      properties: %{
        status: %Schema{
          type: :string,
          enum: ["connected", "disconnected", "connecting"],
          description: "Current VPN connection status"
        },
        vpn_ip: %Schema{
          type: :string,
          nullable: true,
          description: "VPN-assigned IP address",
          example: "100.64.0.10"
        },
        vpn_hostname: %Schema{
          type: :string,
          nullable: true,
          description: "VPN hostname",
          example: "edge-admin"
        },
        connected_at: %Schema{
          type: :string,
          format: :datetime,
          nullable: true,
          description: "When the connection was established"
        },
        last_checked_at: %Schema{
          type: :string,
          format: :datetime,
          description: "Last connectivity check timestamp"
        },
        last_error: %Schema{
          type: :string,
          nullable: true,
          description: "Last error message if connection failed"
        },
        last_error_at: %Schema{
          type: :string,
          format: :datetime,
          nullable: true,
          description: "When the last error occurred"
        },
        manual_disconnect: %Schema{
          type: :boolean,
          description: "Whether VPN was manually disconnected (prevents auto-reconnection)"
        }
      },
      required: [:status, :last_checked_at, :manual_disconnect],
      example: %{
        status: "connected",
        vpn_ip: "100.64.0.10",
        vpn_hostname: "edge-admin",
        connected_at: "2024-01-01T12:00:00Z",
        last_checked_at: "2024-01-01T12:05:00Z",
        last_error: nil,
        last_error_at: nil,
        manual_disconnect: false
      }
    })
  end

  defmodule UpdateRequest do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "VPN Connection Update",
      description: "Update VPN connection manual disconnect setting",
      type: :object,
      properties: %{
        manual_disconnect: %Schema{
          type: :boolean,
          description: "Set to true to manually disconnect and prevent auto-reconnection, false to allow reconnection"
        }
      },
      required: [:manual_disconnect],
      example: %{
        manual_disconnect: true
      }
    })
  end

  defmodule ErrorResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Error Response",
      description: "Standard error response",
      type: :object,
      properties: %{
        error: %Schema{
          type: :string,
          description: "Error message"
        },
        message: %Schema{
          type: :string,
          description: "Additional details (optional)"
        },
        details: %Schema{
          type: :string,
          description: "Technical details (optional)"
        }
      },
      required: [:error],
      example: %{
        error: "Invalid request",
        message: "Only 'manual_disconnect' field is allowed for updates and must be a boolean"
      }
    })
  end
end
