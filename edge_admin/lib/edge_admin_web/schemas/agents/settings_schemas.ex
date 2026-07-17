# edge_admin/lib/edge_admin_web/schemas/agents/settings_schemas.ex
defmodule EdgeAdminWeb.Schemas.Agents.SettingsSchemas do
  @moduledoc false
  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule ConfigData do
    @moduledoc false

    schema(%{
      title: "Internal.SettingsConfigData",
      description: "Non-secret settings config for the authenticated agent",
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
        }
      },
      required: [:admin_urls, :core_derp_map_urls],
      example: %{
        admin_urls: ["https://admin-new.example.com", "https://admin-old.example.com"],
        core_derp_map_urls: [
          "https://relay-new.example.com/derpmap/default",
          "https://relay-old.example.com/derpmap/default"
        ]
      }
    })
  end

  defmodule ConfigResponse do
    @moduledoc false

    schema(CommonSchemas.single_response(ConfigData, "Internal.SettingsConfigResponse", "Settings config"))
  end
end
