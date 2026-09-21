# edge_admin/lib/edge_admin_web/schemas/ingress_tunneling/tunnel_connection_schemas.ex
defmodule EdgeAdminWeb.Schemas.IngressTunneling.TunnelConnectionSchemas do
  @moduledoc false

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule TunnelConnectionData do
    @moduledoc false

    schema(%{
      title: "TunnelConnectionData",
      description: "A Tunnel Client connection to an Ingress Node.",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        tunnel_client_id: %Schema{type: :string, format: :uuid},
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
        :tunnel_client_id,
        :node_id,
        :ingress_ipv4_address,
        :ingress_ipv6_address,
        :tunnel_ipv4_address,
        :tunnel_ipv6_address,
        :inserted_at,
        :updated_at
      ]
    })
  end

  defmodule TunnelConnectionSingleResponse do
    @moduledoc false
    schema(
      CommonSchemas.single_response(
        TunnelConnectionData,
        "TunnelConnectionSingleResponse",
        "Single Tunnel Connection response"
      )
    )
  end

  defmodule TunnelConnectionPaginatedResponse do
    @moduledoc false
    schema(
      CommonSchemas.paginated_response(
        TunnelConnectionData,
        "TunnelConnectionPaginatedResponse",
        "Paginated Tunnel Connection response"
      )
    )
  end

  defmodule TunnelConnectionCreateRequest do
    @moduledoc false
    schema(%{
      title: "TunnelConnectionCreateRequest",
      type: :object,
      properties: %{node_id: %Schema{type: :string, format: :uuid, description: "Ingress Node to connect"}},
      required: [:node_id]
    })
  end
end
