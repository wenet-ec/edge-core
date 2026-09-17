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
        inserted_at: %Schema{type: :string, format: :"date-time", description: "When the Tunnel Client was created"},
        updated_at: %Schema{type: :string, format: :"date-time", description: "When the Tunnel Client was last updated"}
      },
      required: [:id, :public_key, :inserted_at, :updated_at]
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
end
