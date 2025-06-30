# edge_admin/lib/edge_admin_web/schemas/vpn/connection_schemas.ex
defmodule EdgeAdminWeb.Schemas.VPN.ConnectionSchemas do
  @moduledoc """
  OpenAPI schemas for VPN Connection resources
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
          description:
            "Controls auto-reconnection behavior - when true, prevents automatic reconnection attempts"
        },
        inserted_at: %Schema{
          type: :string,
          format: :datetime,
          description: "When the connection record was created"
        },
        updated_at: %Schema{
          type: :string,
          format: :datetime,
          description: "When the connection record was last updated"
        }
      },
      required: [:status, :last_checked_at, :manual_disconnect, :inserted_at, :updated_at],
      example: %{
        status: "connected",
        vpn_ip: "100.64.0.10",
        vpn_hostname: "edge-admin",
        connected_at: "2024-01-01T12:00:00Z",
        last_checked_at: "2024-01-01T12:05:00Z",
        last_error: nil,
        last_error_at: nil,
        manual_disconnect: false,
        inserted_at: "2024-01-01T11:00:00Z",
        updated_at: "2024-01-01T12:05:00Z"
      }
    })
  end

  defmodule ConnectionSingleResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "VPN Connection Single Response",
      description: "Single VPN connection response",
      type: :object,
      properties: %{
        data: ConnectionResponse
      },
      required: [:data],
      example: %{
        data: %{
          status: "connected",
          vpn_ip: "100.64.0.10",
          vpn_hostname: "edge-admin",
          connected_at: "2024-01-01T12:00:00Z",
          last_checked_at: "2024-01-01T12:05:00Z",
          last_error: nil,
          last_error_at: nil,
          manual_disconnect: false,
          inserted_at: "2024-01-01T11:00:00Z",
          updated_at: "2024-01-01T12:05:00Z"
        }
      }
    })
  end

  defmodule ConnectionUpdateRequest do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "VPN Connection Update",
      description: "Update VPN connection properties",
      type: :object,
      properties: %{
        manual_disconnect: %Schema{
          type: :boolean,
          description:
            "Controls auto-reconnection behavior - set to true to disable automatic reconnection, false to enable it"
        }
      },
      required: [:manual_disconnect],
      example: %{
        manual_disconnect: true
      }
    })
  end
end
