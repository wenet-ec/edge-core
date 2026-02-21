# edge_admin/lib/edge_admin_web/api_spec.ex
defmodule EdgeAdminWeb.ApiSpec do
  @moduledoc false
  @behaviour OpenApiSpex.OpenApi

  alias EdgeAdminWeb.Router
  alias OpenApiSpex.Components
  alias OpenApiSpex.Info
  alias OpenApiSpex.OpenApi
  alias OpenApiSpex.Paths
  alias OpenApiSpex.SecurityScheme

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [],
      info: %Info{
        title: "Edge Admin API",
        version: "0.2.0",
        description: """
        Edge Admin API - A backend REST API that serves as a wrapper for various systems.
        This API is designed for internal network use only and provides administrative
        functionality for edge computing systems.
        """
      },
      paths: Paths.from_router(Router)
    }
    |> maybe_add_security()
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp maybe_add_security(spec) do
    if Application.get_env(:edge_admin, :auth_enabled, true) do
      %{
        spec
        | components: %Components{
            securitySchemes: %{
              "masterKey" => %SecurityScheme{
                type: "http",
                scheme: "bearer",
                bearerFormat: "opaque",
                description: "Master key for full API access"
              }
            }
          },
          security: [%{"masterKey" => []}]
      }
    else
      spec
    end
  end
end
