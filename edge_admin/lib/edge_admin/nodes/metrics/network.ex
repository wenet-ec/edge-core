# edge_admin/lib/edge_admin/nodes/metrics/network.ex
defmodule EdgeAdmin.Nodes.Metrics.Network do
  @moduledoc false
  use Ecto.Schema

  @derive Jason.Encoder
  @primary_key false
  embedded_schema do
    field(:rx_bytes_per_sec, :float)
    field(:tx_bytes_per_sec, :float)
    field(:rx_packets_per_sec, :float)
    field(:tx_packets_per_sec, :float)
  end
end
