# edge_admin/lib/edge_admin/nodes/schemas/alias.ex
defmodule EdgeAdmin.Nodes.Schemas.Alias do
  @moduledoc """
  Schema for node aliases.

  Each alias creates a custom DNS entry for a node, allowing it to be addressed
  by a human-friendly name instead of its UUID.

  ## Fields

  - `name` - Alias name (lowercase alphanumeric with hyphens, 1-63 chars)
  - `node_id` - Foreign key to node
  - `cluster_id` - Foreign key to cluster (denormalized for uniqueness constraint)
  - `vpn_hostname` - Virtual field: Full VPN hostname for this alias

  ## Constraints

  Aliases are unique per cluster (same name can exist in different clusters).
  """
  use EdgeAdmin.Schema

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Vpn

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          vpn_hostname: String.t() | nil,
          node_id: String.t(),
          cluster_id: String.t(),
          node: EdgeAdmin.Nodes.Schemas.Node.t() | NotLoaded.t(),
          cluster: Cluster.t() | NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @derive {
    Flop.Schema,
    filterable: [:name, :node_id, :inserted_at, :updated_at],
    sortable: [:name, :inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  schema "aliases" do
    field(:name, :string)
    field(:vpn_hostname, :string, virtual: true)

    belongs_to(:node, EdgeAdmin.Nodes.Schemas.Node)
    belongs_to(:cluster, Cluster)

    timestamps()
  end

  @doc false
  def changeset(alias_record, attrs) do
    alias_record
    |> cast(attrs, [:name, :node_id, :cluster_id])
    |> validate_required([:name, :node_id, :cluster_id])
    |> validate_length(:name, min: 1, max: 63)
    |> validate_format(:name, ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/,
      message: "must be lowercase alphanumeric with hyphens, no leading/trailing hyphens"
    )
    |> unique_constraint([:name, :cluster_id], name: :aliases_cluster_id_name_index)
    |> foreign_key_constraint(:node_id)
    |> foreign_key_constraint(:cluster_id)
  end

  @doc """
  Returns the full VPN hostname for this alias.

  ## Format
  `node-{name}.cluster-{cluster_name}.{domain}`

  where domain is configured via `NETMAKER_DEFAULT_DOMAIN` (default: `nm.internal`)

  ## Requirements
  Requires cluster association to be preloaded.

  ## Examples

      iex> vpn_hostname(%Alias{name: "web", cluster: %Cluster{name: "prod"}})
      "node-web.cluster-prod.nm.internal"
  """
  @spec vpn_hostname(t()) :: String.t()
  def vpn_hostname(%__MODULE__{name: name, cluster: %{name: cluster_name}}) do
    short_name = Vpn.build_vpn_name(name, prefix: :node)
    network_name = Vpn.build_network_name(cluster_name, prefix: :node)
    Vpn.build_vpn_hostname(short_name, network_name)
  end

  @doc """
  Returns the DNS name as stored in Netmaker (without the domain suffix).

  Netmaker stores custom DNS entries WITHOUT the default domain and appends
  it in `GetCustomDNS` when serving entries. Sending the full FQDN causes
  double-suffixing (e.g. `node-web.cluster-prod.nm.internal.nm.internal`).

  Use this when creating or deleting DNS entries via the Netmaker API.
  Use `vpn_hostname/1` for the user-facing fully qualified hostname.

  ## Format
  `node-{name}.cluster-{cluster_name}`

  ## Examples

      iex> netmaker_dns_name(%Alias{name: "web", cluster: %Cluster{name: "prod"}})
      "node-web.cluster-prod"
  """
  @spec netmaker_dns_name(t()) :: String.t()
  def netmaker_dns_name(%__MODULE__{name: name, cluster: %{name: cluster_name}}) do
    "#{Vpn.build_vpn_name(name, prefix: :node)}.#{Vpn.build_network_name(cluster_name, prefix: :node)}"
  end
end
