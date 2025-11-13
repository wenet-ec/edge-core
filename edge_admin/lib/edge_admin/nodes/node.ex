# edge_admin/lib/edge_admin/nodes/node.ex
defmodule EdgeAdmin.Nodes.Node do
  @moduledoc false
  use EdgeAdmin.Schema

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "nodes" do
    belongs_to(:cluster, EdgeAdmin.Nodes.Cluster)

    # Netmaker references
    field(:netmaker_host_id, :binary_id)
    field(:id_type, :string)
    field(:status, :string, default: "online")

    # HTTP communication fields
    field(:http_port, :integer)
    field(:ssh_port, :integer)
    field(:metrics_port, :integer)
    field(:http_proxy_port, :integer)
    field(:socks5_proxy_port, :integer)
    field(:api_token, :string)
    field(:proxy_password, :string)
    field(:last_seen_at, :utc_datetime)

    # Self-update tracking
    field(:version, :string)
    field(:self_update_enabled, :boolean, default: false)

    # Associations
    has_many(:ssh_usernames, EdgeAdmin.Nodes.SshUsername, on_delete: :delete_all)
    has_many(:command_executions, EdgeAdmin.Commands.CommandExecution, on_delete: :nilify_all)
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
      :metrics_port,
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
      :metrics_port,
      :http_proxy_port,
      :socks5_proxy_port
    ])
    |> validate_inclusion(:id_type, ["persistent", "random"])
    |> validate_inclusion(:status, ["online", "offline"])
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
  Returns the DNS hostname for this node.
  Format: node-{id}.cluster-{cluster_id}.{domain}
  where domain is configured via NETMAKER_DEFAULT_DOMAIN (default: nm.internal)
  """
  def dns_hostname(%__MODULE__{id: id, cluster_id: cluster_id}) do
    default_domain = Application.get_env(:edge_admin, :netmaker_default_domain, "nm.internal")
    build_hostname("node-#{id}", "cluster-#{cluster_id}", default_domain)
  end

  @doc """
  Returns the HTTP URL for this node.
  Format: http://node-{id}.cluster-{cluster_id}.{domain}:{port}
  where domain is configured via NETMAKER_DEFAULT_DOMAIN (default: nm.internal)
  """
  def http_url(%__MODULE__{http_port: port} = node) do
    "http://#{dns_hostname(node)}:#{port}"
  end

  defp build_hostname(host, network, ""), do: "#{host}.#{network}"
  defp build_hostname(host, network, domain), do: "#{host}.#{network}.#{domain}"

  def persistent?(%__MODULE__{id_type: "persistent"}), do: true
  def persistent?(_), do: false

  def random?(%__MODULE__{id_type: "random"}), do: true
  def random?(_), do: false
end
