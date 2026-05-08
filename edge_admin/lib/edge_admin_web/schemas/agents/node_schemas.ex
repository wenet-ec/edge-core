# edge_admin/lib/edge_admin_web/schemas/agents/node_schemas.ex
defmodule EdgeAdminWeb.Schemas.Agents.NodeSchemas do
  @moduledoc """
  OpenAPI schemas for agent node registration endpoints.
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule NodeRegisterRequest do
    @moduledoc false

    @id_type_enum Node.id_type_strings()

    schema(%{
      title: "Internal.NodeRegisterRequest",
      description: "Agent registration payload sent on startup",
      type: :object,
      additionalProperties: true,
      properties: %{
        node_id: %Schema{
          type: :string,
          format: :uuid,
          description: "Netmaker node UUID"
        },
        network_name: %Schema{
          type: :string,
          description: "Netmaker network name (must start with 'cluster-')",
          example: "cluster-test"
        },
        id_type: %Schema{
          type: :string,
          enum: @id_type_enum,
          description: "How the node identity is determined"
        },
        http_port: %Schema{
          type: :integer,
          minimum: 1,
          maximum: 65_535,
          description: "Agent HTTP API port admin should reach on this node"
        },
        ssh_port: %Schema{type: :integer, minimum: 1, maximum: 65_535, description: "Agent SSH server port"},
        host_metrics_port: %Schema{
          type: :integer,
          minimum: 1,
          maximum: 65_535,
          description: "Host metrics exporter port"
        },
        wireguard_metrics_port: %Schema{
          type: :integer,
          minimum: 1,
          maximum: 65_535,
          description: "WireGuard metrics exporter port"
        },
        http_proxy_port: %Schema{type: :integer, minimum: 1, maximum: 65_535, description: "HTTP proxy port"},
        socks5_proxy_port: %Schema{type: :integer, minimum: 1, maximum: 65_535, description: "SOCKS5 proxy port"},
        version: %Schema{type: :string, description: "Agent version string", example: "1.2.3"},
        self_update_enabled: %Schema{type: :boolean, description: "Whether the agent supports self-update"}
      },
      required: [
        :node_id,
        :network_name,
        :id_type,
        :http_port,
        :ssh_port,
        :host_metrics_port,
        :wireguard_metrics_port,
        :http_proxy_port,
        :socks5_proxy_port,
        :version,
        :self_update_enabled
      ]
    })
  end

  defmodule NodeHealthCheckRequest do
    @moduledoc false

    schema(%{
      title: "Internal.NodeHealthCheckRequest",
      description: "Agent health status report",
      type: :object,
      additionalProperties: true,
      properties: %{
        status: %Schema{
          type: :string,
          enum: ["healthy", "unhealthy"],
          description: "Current node health status"
        }
      },
      required: [:status]
    })
  end

  defmodule NodeRegistrationData do
    @moduledoc false

    schema(%{
      title: "Internal.NodeRegistrationData",
      description: "Registration credentials and config returned to the agent",
      type: :object,
      properties: %{
        node_id: %Schema{type: :string, format: :uuid, description: "Registered node UUID"},
        api_token: %Schema{type: :string, description: "Bearer token for subsequent authenticated agent requests"},
        proxy_password: %Schema{type: :string, description: "Password for proxy authentication"},
        admin_urls: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "List of admin HTTP fallback URLs"
        },
        derp_map_url: %Schema{type: :string, nullable: true, description: "URL to fetch the DERP relay map"}
      },
      required: [:node_id, :api_token, :proxy_password, :admin_urls],
      example: %{
        node_id: "01234567-89ab-cdef-0123-456789abcdef",
        api_token: "eyJhbGciOiJIUzI1NiJ9...",
        proxy_password: "s3cr3tpassword",
        admin_urls: ["http://10.0.0.1:44000"],
        derp_map_url: "https://controlplane.tailscale.com/derpmap/default"
      }
    })
  end

  defmodule NodeRegistrationResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(
        NodeRegistrationData,
        "Internal.NodeRegistrationResponse",
        "Response after successful agent node registration"
      )
    )
  end

  defmodule NodeHealthCheckData do
    @moduledoc false

    schema(%{
      title: "Internal.NodeHealthCheckData",
      description: "Node identity and status after health report",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, description: "Node UUID"},
        status: %Schema{type: :string, enum: ["healthy", "unhealthy"], description: "Current node health status"},
        last_seen_at: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "Last time the node was seen"
        }
      },
      required: [:id, :status],
      example: %{
        id: "01234567-89ab-cdef-0123-456789abcdef",
        status: "healthy",
        last_seen_at: "2026-04-02T10:00:00Z"
      }
    })
  end

  defmodule NodeHealthCheckResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(
        NodeHealthCheckData,
        "Internal.NodeHealthCheckResponse",
        "Response after reporting node health check status"
      )
    )
  end
end
