# edge_admin/lib/edge_admin/nodes/schemas/node.ex
defmodule EdgeAdmin.Nodes.Schemas.Node do
  @moduledoc false
  use EdgeAdmin.Schema

  alias EdgeAdmin.Vpn

  @derive {
    Flop.Schema,
    filterable: [:id_type, :status, :version, :self_update_enabled, :last_seen_at, :inserted_at],
    sortable: [:id_type, :status, :version, :self_update_enabled, :last_seen_at, :inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "nodes" do
    # Informative fields
    field(:id_type, :string)
    field(:status, :string, default: "healthy")
    field(:last_seen_at, :utc_datetime)
    field(:version, :string)

    # Operational fields
    field(:http_port, :integer)
    field(:ssh_port, :integer)
    field(:host_metrics_port, :integer)
    field(:http_proxy_port, :integer)
    field(:socks5_proxy_port, :integer)
    field(:api_token, :string)
    field(:proxy_password, :string)
    field(:self_update_enabled, :boolean, default: false)

    # Netmaker references
    field(:netmaker_host_id, :binary_id)

    # Computed fields
    field(:node_name, :string, virtual: true)
    field(:dns_hostname, :string, virtual: true)

    # Associations
    belongs_to(:cluster, EdgeAdmin.Nodes.Schemas.Cluster)
    has_many(:ssh_usernames, EdgeAdmin.Ssh.Schemas.SshUsername, on_delete: :delete_all)
    has_many(:aliases, EdgeAdmin.Nodes.Schemas.Alias, on_delete: :delete_all)
    has_many(:command_executions, EdgeAdmin.Commands.Schemas.CommandExecution, on_delete: :nilify_all)
    has_many(:commands, through: [:command_executions, :command])

    timestamps()
  end

  @doc false
  def changeset(node, attrs) do
    node
    |> cast(attrs, [
      :id,
      :cluster_id,
      :netmaker_host_id,
      :id_type,
      :status,
      :http_port,
      :ssh_port,
      :host_metrics_port,
      :http_proxy_port,
      :socks5_proxy_port,
      :api_token,
      :proxy_password,
      :last_seen_at,
      :version,
      :self_update_enabled
    ])
    |> validate_uuid_format(:id)
    |> validate_required([
      :id,
      :cluster_id,
      :id_type,
      :http_port,
      :ssh_port,
      :host_metrics_port,
      :http_proxy_port,
      :socks5_proxy_port,
      :api_token,
      :proxy_password,
      :version,
      :self_update_enabled
    ])
    |> validate_inclusion(:id_type, ["persistent", "random"])
    |> validate_inclusion(:status, ["healthy", "unhealthy", "unreachable"])
    |> unique_constraint(:id, name: :nodes_pkey)
    |> unique_constraint(:api_token)
    |> foreign_key_constraint(:cluster_id)
  end

  defp validate_uuid_format(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case Ecto.UUID.cast(value) do
        {:ok, _} -> []
        :error -> [{field, "must be a valid UUID format"}]
      end
    end)
  end

  @doc """
  Returns the node name for this node.
  Format: node-{id}
  """
  def node_name(%__MODULE__{id: id}) do
    Vpn.build_dns_name(id, prefix: :node)
  end

  @doc """
  Returns the DNS hostname for this node.
  Format: node-{id}.cluster-{cluster_name}.{domain}
  where domain is configured via NETMAKER_DEFAULT_DOMAIN (default: nm.internal)

  Requires cluster association to be preloaded.
  """
  def dns_hostname(%__MODULE__{id: id, cluster: %{name: cluster_name}}) do
    short_name = Vpn.build_dns_name(id, prefix: :node)
    network_name = Vpn.build_network_name(cluster_name, prefix: :node)
    Vpn.build_hostname(short_name, network_name)
  end
end
