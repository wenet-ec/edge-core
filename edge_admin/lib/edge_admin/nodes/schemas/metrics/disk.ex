# edge_admin/lib/edge_admin/nodes/schemas/metrics/disk.ex
defmodule EdgeAdmin.Nodes.Schemas.Metrics.Disk do
  @moduledoc false
  use Ecto.Schema

  @derive Jason.Encoder
  @primary_key false

  embedded_schema do
    field(:usage_percent, :float)
    field(:total_bytes, :integer)
    field(:available_bytes, :integer)
    field(:used_bytes, :integer)
    field(:total_gb, :float)
    field(:available_gb, :float)
    field(:used_gb, :float)
  end
end
