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

  # Explicit path ordering: create → list → get → update → delete per resource.
  # Any path not listed here will be appended at the end in their original order.
  @paths_order [
    # Admins.Metadata
    "/api/v1/admins/self",
    "/api/v1/admins/admin_cluster",
    "/api/v1/admins/edge_clusters",
    "/api/v1/admins/orphaned_clusters",
    # Admins.Metrics
    "/api/v1/admins/metrics/self",
    # Nodes.Cluster
    "/api/v1/clusters",
    "/api/v1/clusters/{name}",
    # Nodes.EnrollmentKey
    "/api/v1/clusters/default/enrollment_keys/public",
    "/api/v1/clusters/default/enrollment_keys",
    "/api/v1/clusters/{cluster_name}/enrollment_keys",
    "/api/v1/enrollment_keys",
    "/api/v1/enrollment_keys/{id}",
    # Nodes.Node
    "/api/v1/nodes",
    "/api/v1/nodes/{id}",
    "/api/v1/nodes/{id}/change_cluster",
    # Nodes.Alias
    "/api/v1/nodes/{node_id}/aliases",
    "/api/v1/aliases",
    "/api/v1/aliases/{id}",
    # Nodes.Metrics
    "/api/v1/nodes/{node_id}/metrics",
    "/api/v1/nodes/{node_id}/metrics/host",
    "/api/v1/nodes/{node_id}/metrics/agent",
    # Commands.Command
    "/api/v1/commands",
    "/api/v1/commands/{id}",
    # Commands.CommandExecution
    "/api/v1/command_executions",
    "/api/v1/command_executions/{id}",
    "/api/v1/command_executions/{id}/cancel",
    # Ssh.SshUsername
    "/api/v1/nodes/{node_id}/ssh_usernames",
    "/api/v1/ssh_usernames",
    "/api/v1/ssh_usernames/{id}",
    # Ssh.SshPublicKey
    "/api/v1/ssh_usernames/{ssh_username_id}/ssh_public_keys",
    "/api/v1/ssh_public_keys",
    "/api/v1/ssh_public_keys/{id}",
    # SelfUpdates.Request
    "/api/v1/self_update_requests",
    "/api/v1/self_update_requests/{id}"
  ]

  @doc "Returns a path → index map for sorting. Paths not listed get index 999_999."
  def paths_order_index do
    @paths_order |> Enum.with_index() |> Map.new()
  end

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
