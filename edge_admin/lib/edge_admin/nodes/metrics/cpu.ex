# edge_admin/lib/edge_admin/nodes/metrics/cpu.ex
defmodule EdgeAdmin.Nodes.Metrics.CPU do
  @derive Jason.Encoder
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:usage_percent, :float)
    field(:cores, :integer)
    field(:load_1m, :float)
    field(:load_5m, :float)
    field(:load_15m, :float)
  end
end
