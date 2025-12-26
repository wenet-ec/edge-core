# edge_admin/lib/edge_admin/metrics/schemas/host_metrics/uptime.ex
defmodule EdgeAdmin.Metrics.Schemas.HostMetrics.Uptime do
  @moduledoc false
  use Ecto.Schema

  @derive Jason.Encoder
  @primary_key false
  embedded_schema do
    field(:seconds, :integer)
    field(:human, :string)
  end
end
