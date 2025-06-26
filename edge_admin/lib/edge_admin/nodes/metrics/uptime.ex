# edge_admin/lib/edge_admin/nodes/metrics.ex
defmodule EdgeAdmin.Nodes.Metrics.Uptime do
  @derive Jason.Encoder
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:seconds, :integer)
    field(:human, :string)
  end
end
