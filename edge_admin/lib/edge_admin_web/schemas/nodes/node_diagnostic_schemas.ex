# edge_admin/lib/edge_admin_web/schemas/nodes/node_diagnostic_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.NodeDiagnosticSchemas do
  @moduledoc false
  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule NodeDiagnosticCheck do
    @moduledoc false

    schema(%{
      title: "NodeDiagnosticCheck",
      type: :object,
      properties: %{
        name: %Schema{
          type: :string,
          enum: [
            "wireguard_interface",
            "netclient",
            "networks",
            "configured_peers",
            "derp_map",
            "database",
            "bootstrap",
            "ssh_server",
            "metrics_servers",
            "proxy_servers"
          ]
        },
        status: %Schema{type: :string, enum: ["pass", "warn", "fail"]},
        duration_ms: %Schema{type: :integer, minimum: 0},
        summary: %Schema{type: :string, nullable: true},
        details: %Schema{type: :object, additionalProperties: true}
      },
      required: [:name, :status, :duration_ms, :details]
    })
  end

  defmodule NodeDiagnosticData do
    @moduledoc false

    schema(%{
      title: "NodeDiagnosticData",
      description: "Structured node diagnostic report",
      type: :object,
      properties: %{
        collected_at: %Schema{type: :string, format: :"date-time"},
        overall: %Schema{type: :string, enum: ["pass", "warn", "fail"]},
        checks: %Schema{type: :array, items: NodeDiagnosticCheck}
      },
      required: [:collected_at, :overall, :checks]
    })
  end

  defmodule NodeDiagnosticResponse do
    @moduledoc false

    schema(CommonSchemas.single_response(NodeDiagnosticData, "NodeDiagnosticResponse", "Node diagnostics"))
  end
end
