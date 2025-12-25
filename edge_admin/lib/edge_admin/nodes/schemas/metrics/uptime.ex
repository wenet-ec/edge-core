# edge_admin/lib/edge_admin/nodes/schemas/metrics/uptime.ex
defmodule EdgeAdmin.Nodes.Schemas.Metrics.Uptime do
  @moduledoc false
  use Ecto.Schema

  @derive Jason.Encoder
  @primary_key false
  embedded_schema do
    field(:seconds, :integer)
    field(:human, :string)
  end
end
