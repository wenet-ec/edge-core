# edge_admin/lib/edge_admin_web/schemas/agents/metrics_schemas.ex
defmodule EdgeAdminWeb.Schemas.Agents.MetricsSchemas do
  @moduledoc """
  OpenAPI schemas for agent metrics push endpoints.
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule MetricsCachePushRequest do
    @moduledoc false

    schema(%{
      title: "Internal.MetricsCachePushRequest",
      description: "Metrics payload pushed by agent when VPN is unavailable",
      type: :object,
      additionalProperties: true,
      properties: %{
        metrics_type: %Schema{
          type: :string,
          enum: ["host", "agent", "wireguard"],
          description: "Type of metrics being pushed"
        },
        metrics_text: %Schema{
          type: :string,
          description: "Raw Prometheus text format metrics"
        }
      },
      required: [:metrics_type, :metrics_text]
    })
  end

  defmodule MetricsCachePushData do
    @moduledoc false

    schema(%{
      title: "Internal.MetricsCachePushData",
      description: "Metrics cache record after a successful push",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, description: "Cache record UUID"},
        node_id: %Schema{type: :string, format: :uuid, description: "Node UUID"},
        metrics_type: %Schema{
          type: :string,
          enum: ["host", "agent", "wireguard"],
          description: "Type of metrics stored"
        },
        updated_at: %Schema{type: :string, format: :"date-time", description: "When the cache was last updated"}
      },
      required: [:id, :node_id, :metrics_type, :updated_at],
      example: %{
        id: "01234567-89ab-cdef-0123-456789abcdef",
        node_id: "abcdef01-2345-6789-abcd-ef0123456789",
        metrics_type: "host",
        updated_at: "2026-04-02T10:00:00Z"
      }
    })
  end

  defmodule MetricsCachePushResponse do
    @moduledoc false

    schema(
      CommonSchemas.single_response(
        MetricsCachePushData,
        "Internal.MetricsCachePushResponse",
        "Metrics cache record after a successful push"
      )
    )
  end
end
