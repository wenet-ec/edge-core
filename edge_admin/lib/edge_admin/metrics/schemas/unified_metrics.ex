# edge_admin/lib/edge_admin/metrics/schemas/unified_metrics.ex
defmodule EdgeAdmin.Metrics.Schemas.UnifiedMetrics do
  @moduledoc """
  Schema for unified metrics aggregating multiple sources for a single node.

  Combines host metrics (Node Exporter) and agent metrics (PromEx) into one
  envelope. Each source carries its own `available` flag — best-effort
  fetching means one source can fail while the other still returns. The
  whole envelope is always returned successfully (no top-level error case).

  Each source is represented as a map. Successful and failed sources have
  different map shapes, so they remain maps rather than nested structs.
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
