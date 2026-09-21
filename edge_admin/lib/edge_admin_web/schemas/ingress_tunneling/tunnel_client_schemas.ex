# edge_admin/lib/edge_admin_web/schemas/ingress_tunneling/tunnel_client_schemas.ex
defmodule EdgeAdminWeb.Schemas.IngressTunneling.TunnelClientSchemas do
  @moduledoc false

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule TunnelClientData do
    @moduledoc false

    schema(%{
      title: "TunnelClient",
      description: "An Admin-managed external Tunnel Client WireGuard identity.",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, description: "Tunnel Client identifier"},
        public_key: %Schema{
          type: :string,
          format: :byte,
          minLength: 44,
          maxLength: 44,
          description: "Canonical base64-encoded X25519 WireGuard public key",
          example: "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE="
        },
        tunnel_connections: %Schema{
          type: :array,
          description: "Connections belonging to this Tunnel Client",
          items: %Schema{
            type: :object,
            properties: %{
              id: %Schema{type: :string, format: :uuid},
              node_id: %Schema{type: :string, format: :uuid},
              ingress_ipv4_address: %Schema{type: :string, example: "10.240.0.1/32"},
              ingress_ipv6_address: %Schema{type: :string, example: "fd20:240::1/128"},
              tunnel_ipv4_address: %Schema{type: :string, example: "10.240.0.2/32"},
              tunnel_ipv6_address: %Schema{type: :string, example: "fd20:240::2/128"},
              inserted_at: %Schema{type: :string, format: :"date-time"},
              updated_at: %Schema{type: :string, format: :"date-time"}
            },
            required: [
              :id,
              :node_id,
              :ingress_ipv4_address,
              :ingress_ipv6_address,
              :tunnel_ipv4_address,
              :tunnel_ipv6_address,
              :inserted_at,
              :updated_at
            ]
          }
        },
        inserted_at: %Schema{type: :string, format: :"date-time", description: "When the Tunnel Client was created"},
        updated_at: %Schema{type: :string, format: :"date-time", description: "When the Tunnel Client was last updated"}
      },
      required: [:id, :public_key, :tunnel_connections, :inserted_at, :updated_at]
    })
  end

  defmodule TunnelClientSingleResponse do
    @moduledoc false
    schema(
      CommonSchemas.single_response(TunnelClientData, "TunnelClientSingleResponse", "Single Tunnel Client response")
    )
  end

  defmodule TunnelClientPaginatedResponse do
    @moduledoc false

    schema(
      CommonSchemas.paginated_response(
        TunnelClientData,
        "TunnelClientPaginatedResponse",
        "Paginated Tunnel Client list response"
      )
    )
  end

  defmodule TunnelClientCreateRequest do
    @moduledoc false
    schema(%{
      title: "TunnelClientCreateRequest",
      description: "Create a Tunnel Client, optionally creating connections to Ingress Nodes.",
      type: :object,
      properties: %{
        node_ids: %Schema{
          type: :array,
          items: %Schema{type: :string, format: :uuid},
          description: "Optional Ingress Node IDs"
        }
      },
      required: []
    })
  end
end
