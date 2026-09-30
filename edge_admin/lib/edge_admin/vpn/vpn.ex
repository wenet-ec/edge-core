# edge_admin/lib/edge_admin/vpn/vpn.ex
defmodule EdgeAdmin.Vpn do
  @moduledoc """
  Public Edge VPN boundary for Edge Admin.

  Naming, addressing, network, host, CLI, administrator-account, and DNS
  operations are implemented by focused modules under `EdgeAdmin.Vpn`.
  """

  alias EdgeAdmin.Vpn.Addressing
  alias EdgeAdmin.Vpn.AdminAccounts
  alias EdgeAdmin.Vpn.Api
  alias EdgeAdmin.Vpn.Cli
  alias EdgeAdmin.Vpn.Dns
  alias EdgeAdmin.Vpn.Hosts
  alias EdgeAdmin.Vpn.Naming
  alias EdgeAdmin.Vpn.Networks

  @doc "Returns the default Edge VPN DNS domain suffix configured by `EDGE_VPN_DEFAULT_DOMAIN`."
  @spec default_domain() :: String.t()
  defdelegate default_domain(), to: Naming

  @doc "Returns the configured Admin cluster network name."
  @spec admin_cluster_name() :: String.t() | nil
  def admin_cluster_name, do: Application.get_env(:edge_admin, :admin_cluster_name)

  @doc "Returns the number of IPv4 slots reserved for Admin Gateway nodes."
  @spec admin_gateway_slot_reservation() :: non_neg_integer()
  def admin_gateway_slot_reservation, do: Application.get_env(:edge_admin, :admin_gateway_slot_reservation, 10)

  @spec usable_ipv4_capacity(0..32) :: non_neg_integer()
  defdelegate usable_ipv4_capacity(prefix), to: Addressing

  @spec build_vpn_name(String.t(), keyword()) :: String.t()
  defdelegate build_vpn_name(name, opts \\ []), to: Naming

  @spec build_network_name(String.t(), keyword()) :: String.t()
  defdelegate build_network_name(name, opts \\ []), to: Naming

  @spec build_vpn_domain(String.t(), String.t() | nil) :: String.t()
  defdelegate build_vpn_domain(network, domain \\ nil), to: Naming

  @spec build_vpn_hostname(String.t(), String.t(), String.t() | nil) :: String.t()
  defdelegate build_vpn_hostname(host, network, domain \\ nil), to: Naming

  @spec build_admin_erlang_node_name(String.t()) :: atom()
  defdelegate build_admin_erlang_node_name(hostname), to: Naming

  @spec validate_network_name(String.t()) :: :ok | {:error, String.t()}
  defdelegate validate_network_name(name), to: Naming

  @spec parse_cidr(String.t()) :: {:ok, tuple()} | {:error, String.t()}
  defdelegate parse_cidr(cidr), to: Addressing

  @spec normalize_ipv4_cidr(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defdelegate normalize_ipv4_cidr(cidr), to: Addressing

  @spec normalize_ipv4_cidr!(String.t()) :: String.t()
  defdelegate normalize_ipv4_cidr!(cidr), to: Addressing

  @spec normalize_ipv4_ranges!([String.t()], keyword()) :: [String.t()]
  defdelegate normalize_ipv4_ranges!(ranges, opts \\ []), to: Addressing

  @spec ensure_disjoint_ipv4_ranges!([String.t()]) :: [String.t()]
  defdelegate ensure_disjoint_ipv4_ranges!(ranges), to: Addressing

  @spec generate_next_subnet([String.t()]) :: {:ok, String.t()} | {:error, {:conflict, String.t()}}
  defdelegate generate_next_subnet(existing_ranges \\ []), to: Addressing

  @spec generate_next_ipv6_subnet([String.t()]) :: {:ok, String.t()} | {:error, {:conflict, String.t()}}
  defdelegate generate_next_ipv6_subnet(existing_ranges \\ []), to: Addressing

  @spec parse_ipv6_cidr(String.t()) :: {:ok, tuple()} | {:error, String.t()}
  defdelegate parse_ipv6_cidr(cidr), to: Addressing

  @spec normalize_ipv6_cidr(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defdelegate normalize_ipv6_cidr(cidr), to: Addressing

  @spec normalize_ipv6_cidr!(String.t()) :: String.t()
  defdelegate normalize_ipv6_cidr!(cidr), to: Addressing

  @spec normalize_ipv6_ranges!([String.t()], keyword()) :: [String.t()]
  defdelegate normalize_ipv6_ranges!(ranges, opts \\ []), to: Addressing

  @spec ensure_disjoint_ipv6_ranges!([String.t()]) :: [String.t()]
  defdelegate ensure_disjoint_ipv6_ranges!(ranges), to: Addressing

  @spec ipv6_cidrs_overlap?(String.t(), [String.t()]) :: boolean()
  defdelegate ipv6_cidrs_overlap?(cidr, existing_ranges), to: Addressing

  @spec ipv4_cidrs_overlap?(String.t(), [String.t()]) :: boolean()
  defdelegate ipv4_cidrs_overlap?(cidr, existing_ranges), to: Addressing

  @doc "Lists all Edge VPN networks."
  @spec list_networks() :: {:ok, [map()]} | {:error, :service_unavailable}
  defdelegate list_networks(), to: Networks

  @doc """
  Returns every IPv4 and IPv6 range assigned across all Edge VPN networks.

  This inventory includes Admin-mesh and cluster networks and is the authoritative
  input to CIDR overlap checks and automatic subnet allocation. It returns an
  error when Edge VPN cannot be queried.
  """
  @spec list_network_ranges() ::
          {:ok, %{ipv4: [String.t()], ipv6: [String.t()]}} | {:error, :service_unavailable}
  defdelegate list_network_ranges(), to: Networks

  @doc """
  Lists Admin-cluster networks with their current nodes and hosts.

  Network, node, and host values retain the Edge VPN response shape. Memberships
  may be stale; callers are responsible for converting them to domain data.
  """
  @spec list_admin_cluster_networks() :: {:ok, [map()]} | {:error, :service_unavailable}
  defdelegate list_admin_cluster_networks(), to: Networks

  @doc """
  Creates an Edge VPN network.

  Existing names return `:already_exists`; overlapping CIDRs return a conflict.
  """
  @spec create_network(String.t(), map()) ::
          {:ok, map()}
          | {:error, :already_exists | :service_unavailable | String.t() | {:conflict, String.t()}}
  defdelegate create_network(network_name, opts \\ %{}), to: Networks

  @doc "Deletes an Edge VPN network."
  @spec delete_network(String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  defdelegate delete_network(network_name), to: Networks

  @doc "Gets an Edge VPN network by name."
  @spec get_network(String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  defdelegate get_network(network_name), to: Networks

  @doc """
  Ensures a network exists with the requested address ranges.

  Before creation, checks the global network inventory for overlapping CIDRs.
  If another replica creates the same network concurrently, verifies that its
  immutable address ranges match the requested values.
  """
  @spec ensure_network_exists(String.t(), map()) ::
          :ok | {:error, String.t() | :service_unavailable | {:conflict, String.t()}}
  defdelegate ensure_network_exists(network_name, create_opts \\ %{}), to: Networks

  @doc """
  Checks whether a network has capacity for another node.

  Capacity accounts for the address Edge VPN reserves during IPv4 allocation;
  a full network is reported before a subsequent join is guaranteed to fail.
  """
  @spec network_has_capacity(String.t()) ::
          :ok
          | {:error, {:network_full, %{used: non_neg_integer(), capacity: non_neg_integer(), network: String.t()}}}
          | {:error, :not_found | :service_unavailable}
  defdelegate network_has_capacity(network_name), to: Networks

  @doc "Lists nodes in an Edge VPN network."
  @spec list_nodes(String.t()) :: {:ok, [map()]} | {:error, :not_found | :service_unavailable}
  defdelegate list_nodes(network_name), to: Networks

  @doc "Reads the local Edge VPN node memberships and addresses from the CLI."
  @spec read_local_vpn_nodes() :: {:ok, [map()]} | {:error, term()}
  defdelegate read_local_vpn_nodes(), to: Cli

  @doc "Reads the locally enrolled Edge VPN host ID from the CLI."
  @spec read_local_vpn_host_id() :: {:ok, String.t()} | {:error, term()}
  defdelegate read_local_vpn_host_id(), to: Cli

  @doc "Removes a host from an Edge VPN network."
  @spec remove_host_from_network(String.t(), String.t()) ::
          {:ok, map()} | {:error, :not_found | :service_unavailable}
  defdelegate remove_host_from_network(host_id, network_name), to: Networks

  @doc """
  Adds a host to a network.

  Edge VPN may report an already-joined host as an HTTP error; this is returned
  as `{:ok, :already_joined}`.
  """
  @spec add_host_to_network(String.t(), String.t()) ::
          {:ok, map()} | {:ok, :already_joined} | {:error, :not_found | :service_unavailable}
  defdelegate add_host_to_network(host_id, network_name), to: Networks

  @doc """
  Resolves a hostname to an Edge VPN host ID, optionally scoped to a network.

  When multiple records share a hostname, selects the best-matching current
  network member. A missing hostname returns `:host_not_found`; an absent
  network returns `:not_found`.
  """
  @spec get_host_id(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, :host_not_found | :not_found | :service_unavailable}
  defdelegate get_host_id(hostname, opts \\ []), to: Hosts

  @doc "Lists the global Edge VPN host inventory, fetching all pages."
  @spec list_hosts() :: {:ok, [map()]} | {:error, :service_unavailable}
  defdelegate list_hosts(), to: Hosts

  @doc "Gets an Edge VPN host by ID."
  @spec get_host(String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  defdelegate get_host(host_id), to: Hosts

  @doc "Deletes an Edge VPN host."
  @spec delete_host(String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  defdelegate delete_host(host_id), to: Hosts

  @doc "Force-deletes an Edge VPN node by network and node ID."
  @spec delete_node(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  defdelegate delete_node(network_name, node_id), to: Networks

  @doc "Gets the default enrollment-key token for an Edge VPN network."
  @spec get_default_enrollment_key(String.t()) :: {:ok, String.t()} | {:error, :default_key_not_found}
  defdelegate get_default_enrollment_key(network_name), to: Networks

  @doc "Joins an Edge VPN network using the local CLI."
  @spec join_network(keyword()) :: {:ok, map()} | {:error, term()}
  defdelegate join_network(opts), to: Cli

  @doc "Checks the local Edge VPN CLI connection health."
  @spec cli_health_check(keyword()) :: {:ok, :healthy | :degraded | :unhealthy, map()}
  defdelegate cli_health_check(opts \\ []), to: Cli, as: :health_check

  @doc "Pulls Edge VPN configuration unless periodic pulls are disabled."
  @spec pull_vpn_config() :: :ok | {:error, term()}
  defdelegate pull_vpn_config(), to: Cli

  @doc "Checks Edge VPN API health via its status endpoint."
  @spec api_health_check(keyword()) :: :ok | {:error, :service_unavailable}
  defdelegate api_health_check(opts \\ []), to: Api, as: :health_check

  @doc "Checks whether the Edge VPN administrator account exists."
  @spec check_admin_account() :: {:ok, boolean()} | {:error, :service_unavailable}
  defdelegate check_admin_account(), to: AdminAccounts

  @doc """
  Creates the Edge VPN administrator account.

  A concurrent duplicate creation is returned as `:already_exists`; other API
  failures become `:service_unavailable`.
  """
  @spec create_admin_account(map()) :: {:ok, map()} | {:error, :already_exists | :service_unavailable}
  defdelegate create_admin_account(attrs), to: AdminAccounts

  @doc "Creates a custom DNS entry in an Edge VPN network."
  @spec create_dns_entry(String.t(), map()) :: {:ok, map()} | {:error, :service_unavailable}
  defdelegate create_dns_entry(network_name, attrs), to: Dns

  @doc "Lists only custom DNS entries for a network, excluding generated node entries."
  @spec list_custom_dns_entries(String.t()) :: {:ok, [map()]} | {:error, :service_unavailable}
  defdelegate list_custom_dns_entries(network_name), to: Dns

  @doc "Deletes a custom DNS entry from a network."
  @spec delete_dns_entry(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  defdelegate delete_dns_entry(network_name, dns_name), to: Dns

  @doc "Finds a network node by its host ID."
  @spec find_node_by_host(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  defdelegate find_node_by_host(network_name, host_id), to: Networks
end
