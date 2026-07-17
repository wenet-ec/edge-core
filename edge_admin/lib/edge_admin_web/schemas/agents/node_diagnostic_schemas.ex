# edge_admin/lib/edge_admin_web/schemas/agents/node_diagnostic_schemas.ex
defmodule EdgeAdminWeb.Schemas.Agents.NodeDiagnosticSchemas do
  @moduledoc false
  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias EdgeAdminWeb.Schemas.Nodes.NodeDiagnosticSchemas.NodeDiagnosticCheck
  alias OpenApiSpex.Schema

  defmodule NodeDiagnosticSnapshot do
    @moduledoc false

    schema(%{
      title: "Internal.NodeDiagnosticSnapshot",
      type: :object,
      properties: %{
        collected_at: %Schema{type: :string, format: :"date-time"},
        overall: %Schema{type: :string, enum: ["pass", "warn", "fail"]},
        checks: %Schema{type: :array, items: NodeDiagnosticCheck}
      },
      required: [:collected_at, :overall, :checks]
    })
  end

  defmodule NodeDiagnosticPushRequest do
    @moduledoc false

    schema(%{
      title: "Internal.NodeDiagnosticPushRequest",
      description: "Latest Agent diagnostic report",
      type: :object,
      properties: %{
        diagnostic: NodeDiagnosticSnapshot
      },
      required: [:diagnostic]
    })
  end

  defmodule NodeDiagnosticPushData do
    @moduledoc false

    schema(%{
      title: "Internal.NodeDiagnosticPushData",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        node_id: %Schema{type: :string, format: :uuid},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :node_id, :updated_at]
    })
  end

  defmodule NodeDiagnosticPushResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(
        NodeDiagnosticPushData,
        "Internal.NodeDiagnosticPushResponse",
        "Diagnostics push acknowledgement"
      )
    )
  end
end
