# edge_admin/lib/edge_admin_web/schemas/agents/setting_schema.ex
defmodule EdgeAdminWeb.Schemas.Agents.SettingSchema do
  @moduledoc false
  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule EmbeddedPeerData do
    @moduledoc false

    schema(%{
      title: "EmbeddedPeerData",
      type: :object,
      properties: %{
        tunnel_connection_id: %Schema{type: :string, format: :uuid},
        tunnel_public_key: %Schema{type: :string},
        tunnel_ipv4_address: %Schema{type: :string},
        tunnel_ipv6_address: %Schema{type: :string},
        allowed_ips: %Schema{type: :array, items: %Schema{type: :string}}
      },
      required: [
        :tunnel_connection_id,
        :tunnel_public_key,
        :tunnel_ipv4_address,
        :tunnel_ipv6_address,
        :allowed_ips
      ]
    })
  end

  defmodule IngressTunnelingData do
    @moduledoc false

    alias EdgeAdminWeb.Schemas.Agents.SettingSchema.EmbeddedPeerData

    schema(%{
      title: "IngressTunnelingData",
      description: "Complete current Ingress Tunneling configuration for one authenticated Agent Node",
      type: :object,
      properties: %{
        ingress_public_key: %Schema{type: :string},
        ingress_ipv4_address: %Schema{type: :string, nullable: true},
        ingress_ipv6_address: %Schema{type: :string, nullable: true},
        vpn_dns_suffix: %Schema{type: :string},
        vpn_ipv4_range: %Schema{type: :string},
        vpn_ipv6_range: %Schema{type: :string},
        core_derp_map_urls: %Schema{type: :array, items: %Schema{type: :string}},
        peers: %Schema{type: :array, items: EmbeddedPeerData}
      },
      required: [
        :ingress_public_key,
        :ingress_ipv4_address,
        :ingress_ipv6_address,
        :vpn_dns_suffix,
        :vpn_ipv4_range,
        :vpn_ipv6_range,
        :core_derp_map_urls,
        :peers
      ]
    })
  end

  defmodule ConfigData do
    @moduledoc false

    alias EdgeAdminWeb.Schemas.Agents.SettingSchema.IngressTunnelingData

    schema(%{
      title: "Internal.SettingsConfigData",
      description: "Non-secret settings config and Ingress Tunneling configuration for the authenticated agent",
      type: :object,
      properties: %{
        admin_urls: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Ordered public Admin fallback URLs"
        },
        core_derp_map_urls: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Ordered mirror or migration URLs for one canonical Core DERP map"
        },
        ingress_tunneling: IngressTunnelingData
      },
      required: [:admin_urls, :core_derp_map_urls, :ingress_tunneling],
      example: %{
        admin_urls: ["https://admin-new.example.com", "https://admin-old.example.com"],
        core_derp_map_urls: [
          "https://relay-new.example.com/derpmap/default",
          "https://relay-old.example.com/derpmap/default"
        ],
        ingress_tunneling: %{
          ingress_public_key: "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=",
          ingress_ipv4_address: "10.240.0.1/32",
          ingress_ipv6_address: "fd20:240::1/128",
          vpn_dns_suffix: "cluster-1.nm.internal",
          vpn_ipv4_range: "100.64.0.0/24",
          vpn_ipv6_range: "fd7a:91c2:4e8c:1::/64",
          core_derp_map_urls: ["https://relay.example.com/derpmap/default"],
          peers: []
        }
      }
    })
  end

  defmodule ConfigResponse do
    @moduledoc false

    schema(CommonSchemas.single_response(ConfigData, "Internal.SettingsConfigResponse", "Settings config"))
  end
end
