# edge_admin/lib/edge_admin/metrics/schemas/node_metrics_cache.ex
defmodule EdgeAdmin.Metrics.Schemas.NodeMetricsCache do
  @moduledoc """
  Schema for storing node metrics temporarily when VPN is unavailable.

  Acts as a fallback cache allowing admin to serve metrics to collectors even
  when VPN connectivity is down. Metrics are pushed by agents via HTTP fallback.

  Staleness is enforced at read time, not by deletion: rows are never removed.
  `EdgeAdmin.Metrics.get_cached_metrics/2` filters out anything older than the
  fixed 5-minute window (`@cache_staleness_minutes`). Subsequent pushes overwrite
  the row in place via the `(node_id, metrics_type)` upsert, so each node holds
  at most one row per metrics type for the lifetime of the node.
  """
  use EdgeAdmin.Schema

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.Nodes.Schemas.Node

  @type t :: %__MODULE__{
          id: String.t(),
          metrics_type: String.t(),
          metrics_text: String.t(),
          node_id: String.t(),
          node: Node.t() | NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "node_metrics_cache" do
    field :metrics_type, :string
    field :metrics_text, :string

    # Associations
    belongs_to :node, Node

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
