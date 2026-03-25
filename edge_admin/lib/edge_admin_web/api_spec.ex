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
  alias OpenApiSpex.Tag

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
      paths: Paths.from_router(Router),
      tags: [
        %Tag{name: "Admins.Metadata"},
        %Tag{name: "Admins.Metrics"},
        %Tag{name: "Nodes.Cluster"},
        %Tag{name: "Nodes.EnrollmentKey"},
        %Tag{name: "Nodes.Node"},
        %Tag{name: "Nodes.Alias"},
        %Tag{name: "Nodes.Metrics"},
        %Tag{name: "Commands.Command"},
        %Tag{name: "Commands.CommandExecution"},
        %Tag{name: "Ssh.SshUsername"},
        %Tag{name: "Ssh.SshPublicKey"},
        %Tag{name: "SelfUpdates.Request"}
      ]
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
              "apiKey" => %SecurityScheme{
                type: "http",
                scheme: "bearer",
                bearerFormat: "opaque",
                description: "API key for REST API access (API_KEY or MASTER_KEY)"
              }
            }
          },
          security: [%{"apiKey" => []}]
      }
    else
      spec
    end
  end
end
