# edge_admin/lib/edge_admin/metrics/schemas/node_metrics_cache.ex
defmodule EdgeAdmin.Metrics.Schemas.NodeMetricsCache do
  @moduledoc """
  Schema for storing node metrics temporarily when VPN is unavailable.

  Acts as a fallback cache allowing admin to serve metrics to collectors
  even when VPN connectivity is down. Metrics are pushed by agents via
  HTTP fallback and expire after a configured TTL.
  """
  use EdgeAdmin.Schema

  schema "node_metrics_cache" do
    field :metrics_type, :string
    field :metrics_text, :string

    # Associations
    belongs_to :node, EdgeAdmin.Nodes.Schemas.Node

    timestamps()
  end

  @doc false
  def changeset(cache, attrs) do
    cache
    |> cast(attrs, [:node_id, :metrics_type, :metrics_text])
    |> validate_required([:node_id, :metrics_type, :metrics_text])
    |> validate_inclusion(:metrics_type, ["host", "agent", "wireguard"])
    |> unique_constraint([:node_id, :metrics_type],
      name: :node_metrics_cache_node_id_metrics_type_index
    )
  end
end
