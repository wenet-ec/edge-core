# edge_admin/lib/edge_admin/nodes/schemas/node.ex
defmodule EdgeAdmin.Nodes.Schemas.Node do
  @moduledoc """
  Schema for edge agent nodes.

  Each node represents an edge device running the EdgeAgent application.
  Nodes are enrolled via enrollment keys and belong to a cluster (VPN network).

  ## Fields

  - `id` - Node UUID (can be persistent or randomly generated per boot)
  - `id_type` - Either `:persistent` (saved to disk) or `:random` (ephemeral)
  - `status` - Health status: `:healthy`, `:unhealthy`, or `:unreachable`
  - `cluster_id` - Foreign key to cluster
  - `netmaker_host_id` - Reference to Netmaker host resource
  - `api_token` - Bearer token for node API authentication
  - `proxy_password` - Password for proxy server authentication
  - `http_port`, `ssh_port`, etc. - Service ports exposed by the node
  - `last_seen_at` - Last successful health check timestamp
  - `version` - EdgeAgent version string
  - `self_update_enabled` - Whether auto-updates are enabled
  """
  use EdgeAdmin.Schema

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Ssh.Schemas.SshUsername
  alias EdgeAdmin.Vpn

  # Health status registry. The schema's `Ecto.Enum` cast, the public predicate
  # functions, and external surfaces (controller / MCP / OpenAPI / AsyncAPI
  # enums) all derive from these lists — single source of truth.
  @statuses [:healthy, :unhealthy, :unreachable]
  @reachable_statuses [:healthy, :unhealthy]

  # ID-type registry. Same pattern as @statuses above.
  @id_types [:persistent, :random]

  @type status :: :healthy | :unhealthy | :unreachable
  @type id_type :: :persistent | :random

  @type t :: %__MODULE__{
          id: String.t(),
          id_type: id_type(),
          status: status(),
          last_seen_at: DateTime.t() | nil,
          version: String.t(),
          http_port: integer(),
          ssh_port: integer(),
          host_metrics_port: integer(),
          wireguard_metrics_port: integer(),
          http_proxy_port: integer(),
          socks5_proxy_port: integer(),
          api_token: String.t(),
          proxy_password: String.t(),
          self_update_enabled: boolean(),
          netmaker_host_id: String.t(),
          node_name: String.t() | nil,
          vpn_hostname: String.t() | nil,
          mdns_hostname: String.t() | nil,
          cluster_id: String.t(),
          cluster: Cluster.t() | NotLoaded.t(),
          ssh_usernames: [SshUsername.t()] | NotLoaded.t(),
          aliases: [Alias.t()] | NotLoaded.t(),
          command_executions: [CommandExecution.t()] | NotLoaded.t(),
          commands: [EdgeAdmin.Commands.Schemas.Command.t()] | NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @derive {
    Flop.Schema,
    filterable: [:id_type, :status, :version, :self_update_enabled, :last_seen_at, :inserted_at, :updated_at],
    sortable: [
      :id_type,
      :status,
      :version,
      :self_update_enabled,
      :last_seen_at,
      :inserted_at,
      :updated_at
    ],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  @primary_key {:id, Uniq.UUID, autogenerate: false, dump: :raw, type: :uuid}

  schema "nodes" do
    # Informative fields
    field(:id_type, Ecto.Enum, values: @id_types)
    field(:status, Ecto.Enum, values: @statuses, default: :healthy)
    field(:last_seen_at, :utc_datetime)
    field(:version, :string)

    # Operational fields
    field(:http_port, :integer)
    field(:ssh_port, :integer)
    field(:host_metrics_port, :integer)
    field(:wireguard_metrics_port, :integer)
    field(:http_proxy_port, :integer)
    field(:socks5_proxy_port, :integer)
    field(:api_token, :string, redact: true)
    field(:proxy_password, :string, redact: true)
    field(:self_update_enabled, :boolean, default: false)

    # Netmaker references
    field(:netmaker_host_id, :binary_id)

    # Computed fields
    field(:node_name, :string, virtual: true)
    field(:vpn_hostname, :string, virtual: true)
    field(:mdns_hostname, :string, virtual: true)

    # Associations
    belongs_to(:cluster, Cluster)
    has_many(:ssh_usernames, SshUsername, on_delete: :delete_all)
    has_many(:aliases, Alias, on_delete: :delete_all)
    has_many(:command_executions, CommandExecution, on_delete: :nilify_all)
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
      :wireguard_metrics_port,
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
      :wireguard_metrics_port,
      :http_proxy_port,
      :socks5_proxy_port,
      :api_token,
      :proxy_password,
      :version,
      :self_update_enabled
    ])
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

  ## Format
  `node-{id}`

  ## Examples

      iex> node_name(%Node{id: "abc-123"})
      "node-abc-123"
  """
  @spec node_name(t()) :: String.t()
  def node_name(%__MODULE__{id: id}) do
    Vpn.build_vpn_name(id, prefix: :node)
  end

  @doc """
  Returns the VPN hostname for this node.

  ## Format
  `node-{id}.cluster-{cluster_name}.{domain}`

  where domain is configured via `NETMAKER_DEFAULT_DOMAIN` (default: `nm.internal`)

  ## Requirements
  Requires cluster association to be preloaded.

  ## Examples

      iex> vpn_hostname(%Node{id: "abc-123", cluster: %Cluster{name: "prod"}})
      "node-abc-123.cluster-prod.nm.internal"
  """
  @spec vpn_hostname(t()) :: String.t()
  def vpn_hostname(%__MODULE__{id: id, cluster: %{name: cluster_name}}) do
    short_name = Vpn.build_vpn_name(id, prefix: :node)
    network_name = Vpn.build_network_name(cluster_name, prefix: :node)
    Vpn.build_vpn_hostname(short_name, network_name)
  end

  @doc """
  Returns the mDNS hostname for this node.

  ## Format
  `node-{id}.local`

  ## Examples

      iex> mdns_hostname(%Node{id: "abc-123"})
      "node-abc-123.local"
  """
  @spec mdns_hostname(t()) :: String.t()
  def mdns_hostname(%__MODULE__{id: id}) do
    "node-#{id}.local"
  end

  # ---------------------------------------------------------------------------
  # Status registry
  # ---------------------------------------------------------------------------

  @doc "All node health statuses, in canonical order."
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc "Statuses for which the node was reached recently (excludes :unreachable)."
  @spec reachable_statuses() :: [status()]
  def reachable_statuses, do: @reachable_statuses

  @doc "Wire-format strings (sorted to match `statuses/0`). For OpenAPI / MCP / AsyncAPI enums."
  @spec status_strings() :: [String.t()]
  def status_strings, do: Enum.map(@statuses, &Atom.to_string/1)

  @doc "Wire-format strings for reachable statuses only."
  @spec reachable_status_strings() :: [String.t()]
  def reachable_status_strings, do: Enum.map(@reachable_statuses, &Atom.to_string/1)

  # ---------------------------------------------------------------------------
  # ID-type registry
  # ---------------------------------------------------------------------------

  @doc "All node id_types, in canonical order."
  @spec id_types() :: [id_type()]
  def id_types, do: @id_types

  @doc "Wire-format id_type strings (sorted to match `id_types/0`)."
  @spec id_type_strings() :: [String.t()]
  def id_type_strings, do: Enum.map(@id_types, &Atom.to_string/1)
end
