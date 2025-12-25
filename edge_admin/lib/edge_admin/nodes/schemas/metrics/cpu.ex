# edge_admin/lib/edge_admin/nodes/schemas/metrics/cpu.ex
defmodule EdgeAdmin.Nodes.Schemas.Metrics.CPU do
  @moduledoc false
  use Ecto.Schema

  @derive Jason.Encoder
  @primary_key false
  embedded_schema do
    field(:cores, :integer)
    field(:load_1m, :float)
    field(:load_5m, :float)
    field(:load_15m, :float)
  end
end
