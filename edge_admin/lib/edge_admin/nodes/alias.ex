# edge_admin/lib/edge_admin/nodes/alias.ex
defmodule EdgeAdmin.Nodes.Alias do
  @moduledoc """
  Schema for node aliases. Each alias creates a custom DNS entry for a node.
  """
  use EdgeAdmin.Schema

  alias EdgeAdmin.Vpn

  schema "aliases" do
    field(:name, :string)
    field(:dns_hostname, :string, virtual: true)

    belongs_to(:node, EdgeAdmin.Nodes.Node, type: :binary_id)
    belongs_to(:cluster, EdgeAdmin.Nodes.Cluster, type: :binary_id)

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
    |> unique_constraint([:cluster_id, :name], name: :aliases_cluster_id_name_index)
    |> foreign_key_constraint(:node_id)
    |> foreign_key_constraint(:cluster_id)
  end

  @doc """
  Returns the full DNS hostname for this alias.
  Format: node-{name}.cluster-{cluster_name}.{domain}
  where domain is configured via NETMAKER_DEFAULT_DOMAIN (default: nm.internal)

  Requires cluster association to be preloaded.
  """
  def dns_hostname(%__MODULE__{name: name, cluster: %{name: cluster_name}}) do
    short_name = Vpn.build_dns_name(name, prefix: :node)
    network_name = Vpn.build_network_name(cluster_name, prefix: :node)
    Vpn.build_hostname(short_name, network_name)
  end
end
