# edge_admin/lib/edge_admin/nodes/schemas/cluster.ex
defmodule EdgeAdmin.Nodes.Schemas.Cluster do
  @moduledoc """
  Schema for edge clusters.

  Each cluster represents an isolated dual-stack Edge VPN network (VPN).
  Nodes within a cluster can communicate with each other via the VPN.

  ## Fields

  - `name` - Cluster name (lowercase alphanumeric with hyphens, max 24 chars)
  - `ipv4_range` - CIDR notation for the cluster's VPN network (e.g., "100.64.1.0/24")
  - `ipv6_range` - ULA /64 CIDR for the cluster's VPN network
  - `node_limit` - Maximum nodes allowed in this cluster (null means no limit)
  - `deleted_at` - Internal tombstone marking a cluster retired from the public API
  - `network_name` - Virtual field: Edge VPN network name (cluster-{name})
  - `vpn_domain` - Virtual field: VPN domain suffix for nodes in this cluster
  - `node_count` - Virtual field: Number of nodes in this cluster
  """
  use EdgeAdmin.Schema

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Validators.ClusterValidators
  alias EdgeAdmin.Random
  alias EdgeAdmin.Vpn

  # /31 and /32 are unusable for an edge cluster: Edge VPN skips the network
  # address and the remaining addresses are reserved for Admin gateways.
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          ipv4_range: String.t(),
          ipv6_range: String.t(),
          node_limit: integer() | nil,
          deleted_at: DateTime.t() | nil,
          network_name: String.t() | nil,
          vpn_domain: String.t() | nil,
          node_count: integer() | nil,
          nodes: [Node.t()] | NotLoaded.t(),
          enrollment_keys: [EnrollmentKey.t()] | NotLoaded.t(),
          aliases: [Alias.t()] | NotLoaded.t(),
          command_executions: [CommandExecution.t()] | NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @derive {
    Flop.Schema,
    filterable: [:name, :ipv4_range, :ipv6_range, :node_limit, :inserted_at, :updated_at],
    sortable: [:name, :ipv4_range, :ipv6_range, :node_limit, :inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  schema "clusters" do
    field(:name, :string)
    field(:ipv4_range, :string)
    field(:ipv6_range, :string)
    field(:node_limit, :integer)
    field(:deleted_at, :utc_datetime)
    field(:network_name, :string, virtual: true)
    field(:vpn_domain, :string, virtual: true)
    field(:node_count, :integer, virtual: true)

    has_many(:nodes, Node)
    has_many(:enrollment_keys, EnrollmentKey)
    has_many(:aliases, Alias, on_delete: :delete_all)
    has_many(:command_executions, CommandExecution, on_delete: :nilify_all)

    timestamps()
  end

  @doc false
  def changeset(cluster, attrs) do
    cluster
    |> cast(attrs, [:name, :ipv4_range, :ipv6_range, :node_limit])
    |> maybe_generate_name()
    |> validate_required([:name, :ipv4_range, :ipv6_range])
    |> validate_name()
    |> validate_node_limit()
    |> check_constraint(:node_limit, name: :clusters_node_limit_positive)
    |> validate_ipv4_range()
    |> validate_ipv6_range()
    |> validate_node_limit_fits_cidr()
    |> unique_constraint(:name)
    |> unique_constraint(:ipv4_range)
    |> unique_constraint(:ipv6_range)
  end

  @doc """
  Returns the Edge VPN network name for this cluster.

  Format: `cluster-{name}`.
  """
  @spec network_name(t() | String.t()) :: String.t()
  def network_name(%__MODULE__{name: name}), do: Vpn.build_network_name(name, prefix: :node)
  def network_name(name) when is_binary(name), do: Vpn.build_network_name(name, prefix: :node)

  @doc """
  Returns the VPN domain suffix for nodes in this cluster.

  Format: `cluster-{name}.{domain}`, where `domain` comes from
  `EDGE_VPN_DEFAULT_DOMAIN` (default: `nm.internal`).
  """
  @spec vpn_domain(t()) :: String.t()
  def vpn_domain(%__MODULE__{name: name}) do
    Vpn.build_vpn_domain(network_name(name))
  end

  @doc """
  Returns the number of nodes in this cluster.

  Returns `0` when the nodes association is not loaded.
  """
  @spec node_count(t()) :: non_neg_integer()
  def node_count(%__MODULE__{nodes: nodes}) when is_list(nodes), do: length(nodes)
  def node_count(%__MODULE__{}), do: 0

  defp maybe_generate_name(changeset) do
    if get_field(changeset, :name) do
      changeset
    else
      random_name = Random.string(12)

      put_change(changeset, :name, random_name)
    end
  end

  defp validate_name(changeset) do
    validate_change(changeset, :name, fn :name, value ->
      case ClusterValidators.name_error(value) do
        :ok -> []
        {:error, message} -> [name: message]
      end
    end)
  end

  defp validate_node_limit(changeset) do
    validate_change(changeset, :node_limit, fn :node_limit, value ->
      if ClusterValidators.valid_node_limit?(value), do: [], else: [node_limit: "must be greater than 0"]
    end)
  end

  defp validate_ipv4_range(changeset) do
    validate_change(changeset, :ipv4_range, fn _, value ->
      case ClusterValidators.ipv4_range_error(value) do
        :ok -> []
        {:error, reason} -> [ipv4_range: reason]
      end
    end)
  end

  defp validate_ipv6_range(changeset) do
    validate_change(changeset, :ipv6_range, fn _, value ->
      case ClusterValidators.ipv6_range_error(value) do
        :ok ->
          []

        {:error, reason} ->
          [ipv6_range: reason]
      end
    end)
  end

  # Validates node_limit does not exceed usable CIDR capacity after reservations.
  # Only fires when both fields are present and the CIDR is already valid.
  defp validate_node_limit_fits_cidr(changeset) do
    with limit when not is_nil(limit) <- get_field(changeset, :node_limit),
         cidr when not is_nil(cidr) <- get_field(changeset, :ipv4_range),
         {:ok, {_ip, prefix}} <- Vpn.parse_cidr(cidr) do
      reservation = Vpn.admin_slot_reservation()
      max_limit = Vpn.usable_ipv4_capacity(prefix) - reservation

      if ClusterValidators.node_limit_fits_ipv4_range?(limit, cidr, reservation) do
        changeset
      else
        add_error(
          changeset,
          :node_limit,
          "cannot exceed #{max_limit} for /#{prefix} (#{Vpn.usable_ipv4_capacity(prefix)} usable IPs minus #{reservation} Admin slots)"
        )
      end
    else
      _ -> changeset
    end
  end
end
