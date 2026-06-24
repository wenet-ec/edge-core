# edge_admin/lib/edge_admin/metrics/schemas/unified_metrics.ex
defmodule EdgeAdmin.Metrics.Schemas.UnifiedMetrics do
  @moduledoc """
  Schema for unified metrics aggregating multiple sources for a single node.

  Combines host metrics (Node Exporter) and agent metrics (PromEx) into one
  envelope. Each source carries its own `available` flag — best-effort
  fetching means one source can fail while the other still returns. The
  whole envelope is always returned successfully (no top-level error case).

  ## host / agent shape

  When the source succeeded:

      %{
        available: true,
        cpu: ..., memory: ..., disk: ..., uptime: ...    # for host
        application: ..., commands: ..., ...             # for agent
      }

  When the source failed:

      %{available: false, error: "unavailable"}

  These two fields stay maps (not nested structs) because the failure
  branch has a different shape than the success branch. Promoting them
  to structs would force a discriminator.
  """

  @type t :: %__MODULE__{
          node_id: String.t(),
          cluster_name: String.t() | nil,
          timestamp: DateTime.t(),
          host: map(),
          agent: map()
        }

  @derive JSON.Encoder
  defstruct [
    :node_id,
    :cluster_name,
    :timestamp,
    :host,
    :agent
  ]
end
