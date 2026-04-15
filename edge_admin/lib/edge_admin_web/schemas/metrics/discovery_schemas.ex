# edge_admin/lib/edge_admin_web/schemas/metrics/discovery_schemas.ex
defmodule EdgeAdminWeb.Schemas.Metrics.DiscoverySchemas do
  @moduledoc """
  OpenAPI schemas for Prometheus HTTP service discovery endpoints.
  """

  use EdgeAdminWeb.Schema

  alias OpenApiSpex.Schema

  defmodule DiscoveryTargetGroup do
    @moduledoc false

    schema(%{
      title: "Internal.DiscoveryTargetGroup",
      description: "A group of scrape targets with shared labels, in Prometheus http_sd_configs format",
      type: :object,
      properties: %{
        targets: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "List of scrape target URLs",
          example: ["http://10.0.0.1:44000/api/v1/nodes/abc123/metrics/host/raw"]
        },
        labels: %Schema{
          type: :object,
          properties: %{
            cluster: %Schema{type: :string, description: "Cluster name"},
            job: %Schema{type: :string, description: "Prometheus job name"}
          },
          required: [:cluster, :job]
        }
      },
      required: [:targets, :labels],
      example: %{
        targets: ["http://10.0.0.1:44000/api/v1/nodes/abc123/metrics/host/raw"],
        labels: %{cluster: "default", job: "node-host-metrics"}
      }
    })
  end

  defmodule DiscoveryResponse do
    @moduledoc false

    schema(%{
      title: "Internal.DiscoveryResponse",
      description: "List of Prometheus HTTP SD target groups",
      type: :array,
      items: DiscoveryTargetGroup,
      example: [
        %{
          targets: ["http://10.0.0.1:44000/api/v1/nodes/abc123/metrics/host/raw"],
          labels: %{cluster: "default", job: "node-host-metrics"}
        }
      ]
    })
  end
end
