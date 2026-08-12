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
  alias EdgeAdmin.Naming
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Random
  alias EdgeAdmin.Vpn

  # /31 and /32 are unusable for an edge cluster: Edge VPN skips the network
  # address and the remaining addresses are reserved for Admin gateways.
  @min_prefix 30

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
    |> validate_length(:name, max: Naming.cluster_name_max_length())
    |> validate_format(:name, Naming.cluster_name_regex())
    |> validate_exclusion(:name, ~w(default), message: "is reserved")
    |> validate_number(:node_limit, greater_than: 0)
    |> check_constraint(:node_limit, name: :clusters_node_limit_positive)
    |> validate_ipv4_cidr_format()
    |> validate_ipv4_exclusions()
    |> validate_ipv6_cidr()
    |> validate_cidr_minimum_prefix()
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

  defp validate_ipv4_cidr_format(changeset) do
    validate_change(changeset, :ipv4_range, fn _, value ->
      case Vpn.parse_cidr(value) do
        {:ok, _} -> []
        {:error, reason} -> [ipv4_range: reason]
      end
    end)
  end

  defp validate_ipv4_exclusions(changeset) do
    validate_change(changeset, :ipv4_range, fn _, value ->
      case Vpn.parse_cidr(value) do
        {:ok, {ip_tuple, _prefix}} ->
          if excluded_range?(ip_tuple) do
            [ipv4_range: "cannot use private, loopback, link-local, or multicast ranges"]
          else
            []
          end

        {:error, _} ->
          []
      end
    end)
  end

  defp validate_ipv6_cidr(changeset) do
    validate_change(changeset, :ipv6_range, fn _, value ->
      case Vpn.parse_ipv6_cidr(value) do
        {:ok, {ip, 64}} ->
          if ula_ipv6?(ip), do: [], else: [ipv6_range: "must be a private ULA range under fd00::/8"]

        {:ok, {_ip, prefix}} ->
          [ipv6_range: "must use a /64 prefix (got /#{prefix})"]

        {:error, reason} ->
          [ipv6_range: reason]
      end
    end)
  end

  defp ula_ipv6?({first, _, _, _, _, _, _, _}), do: first >= 0xFD00 and first <= 0xFDFF

  defp excluded_range?({a, _, _, _}) do
    a in [0, 10, 127, 169, 172, 192, 224, 240, 255]
  end

  defp validate_cidr_minimum_prefix(changeset) do
    validate_change(changeset, :ipv4_range, fn _, value ->
      case Vpn.parse_cidr(value) do
        {:ok, {_ip, prefix}} when prefix > @min_prefix ->
          [
            ipv4_range:
              "prefix /#{prefix} is too small — minimum is /#{@min_prefix} (#{Vpn.usable_ipv4_capacity(@min_prefix)} usable IPs)"
          ]

        _ ->
          []
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

      if limit > max_limit do
        add_error(
          changeset,
          :node_limit,
          "cannot exceed #{max_limit} for /#{prefix} (#{Vpn.usable_ipv4_capacity(prefix)} usable IPs minus #{reservation} Admin slots)"
        )
      else
        changeset
      end
    else
      _ -> changeset
    end
  end
end
