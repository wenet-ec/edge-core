# edge_admin/lib/edge_admin/vpn/vpn.ex
defmodule EdgeAdmin.Vpn do
  @moduledoc """
  VPN integration and Netmaker API wrapper for Edge Admin.

  This module provides a centralized interface for all VPN-related operations, including:

  - DNS and hostname construction for nodes and admins
  - Netmaker network, host, enrollment key, and DNS entry operations
  - IPv4/IPv6 CIDR parsing, overlap checks, and subnet allocation
  - Error normalization around Nexmaker responses

  Most Netmaker calls route through `normalize_netmaker_error/1`, collapsing
  outcomes to `{:ok, _} | {:error, :not_found} | {:error, :service_unavailable}`.
  Functions where callers need richer outcomes document their narrower
  exceptions, such as `create_network/2`, `add_host_to_network/2`, and
  `network_has_capacity/1`.
  """

  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.Vpn.Addressing, as: VpnAddressing
  alias EdgeAdmin.Vpn.Naming, as: VpnNaming
  alias Nexmaker.Api
  alias Nexmaker.Api.DNS
  alias Nexmaker.Api.EnrollmentKeys
  alias Nexmaker.Api.Hosts
  alias Nexmaker.Api.Networks
  alias Nexmaker.Api.Nodes
  alias Nexmaker.Api.Superadmin

  require Logger

  @doc """
  Returns the default Netmaker DNS domain suffix.
  Configured via EDGE_VPN_DEFAULT_DOMAIN (default: "nm.internal")
  """
  @spec default_domain() :: String.t()
  defdelegate default_domain(), to: VpnNaming

  @doc """
  Returns the admin cluster network name.
  Configured via :admin_cluster_name in application config.
  """
  def admin_cluster_name do
    Application.get_env(:edge_admin, :admin_cluster_name)
  end

  @doc """
  Returns the configured base ranges for auto-generating cluster subnets.
  """
  def cluster_auto_generated_v4_ranges do
    Application.get_env(:edge_admin, :cluster_auto_generated_v4_ranges)
  end

  @doc """
  Returns the target subnet prefix for auto-generated clusters.
  """
  def cluster_v4_subnet_prefix do
    Application.get_env(:edge_admin, :cluster_v4_subnet_prefix)
  end

  @doc "Returns the configured ULA pools used to allocate edge-cluster IPv6 /64s."
  def cluster_auto_generated_v6_ranges do
    Application.get_env(:edge_admin, :cluster_auto_generated_v6_ranges)
  end

  @doc "Returns the target prefix for automatically allocated IPv6 edge networks."
  def cluster_v6_subnet_prefix do
    Application.get_env(:edge_admin, :cluster_v6_subnet_prefix, 64)
  end

  @doc """
  Returns the number of IP slots reserved for admin gateway nodes.

  Should be tuned to match the total number of admin instances across all admin clusters per core.
  """
  def admin_slot_reservation do
    Application.get_env(:edge_admin, :admin_slot_reservation, 10)
  end

  defdelegate usable_ipv4_capacity(prefix), to: VpnAddressing

  defdelegate build_vpn_name(name, opts \\ []), to: VpnNaming
  defdelegate build_network_name(name, opts \\ []), to: VpnNaming
  defdelegate validate_admin_cluster_suffix!(suffix), to: VpnNaming
  defdelegate build_vpn_domain(network, domain \\ nil), to: VpnNaming
  defdelegate build_vpn_hostname(host, network, domain \\ nil), to: VpnNaming
  defdelegate build_admin_erlang_node_name(hostname), to: VpnNaming
  defdelegate validate_network_name(name), to: VpnNaming

  defdelegate parse_cidr(cidr), to: VpnAddressing
  defdelegate parse_ipv4(ip_str), to: VpnAddressing
  defdelegate generate_next_subnet(existing_ranges \\ []), to: VpnAddressing
  defdelegate generate_next_ipv6_subnet(existing_ranges \\ []), to: VpnAddressing
  defdelegate find_available_subnet(base_cidr, target_prefix, existing_ranges), to: VpnAddressing
  defdelegate find_available_ipv6_subnet(base_cidr, target_prefix, existing_ranges), to: VpnAddressing
  defdelegate parse_ipv6_cidr(cidr), to: VpnAddressing
  defdelegate ipv6_cidrs_overlap?(cidr, existing_ranges), to: VpnAddressing
  defdelegate ipv4_cidrs_overlap?(cidr, existing_ranges), to: VpnAddressing
  defdelegate generate_subnets(base_ip, base_prefix, target_prefix), to: VpnAddressing

  @doc """
  Funnel for Netmaker API responses.

  Preserves `{:ok, _}` and `{:error, :not_found}`; collapses every other error
  into `{:error, :service_unavailable}`. Every Netmaker call routes through
  this so callers only have to pattern-match on a small fixed set of outcomes.
  """
  @spec normalize_netmaker_error(term()) :: {:ok, term()} | {:error, :not_found | :service_unavailable}
  def normalize_netmaker_error(result) do
    case Api.normalize(result) do
      {:ok, _} = ok -> ok
      {:error, :not_found} -> {:error, :not_found}
      {:error, _} -> {:error, :service_unavailable}
    end
  end

  @doc """
  Lists all Netmaker networks.

  Returns `{:ok, [network]}` or `{:error, :service_unavailable}`.
  Each network map includes a `"netid"` field with the network name.
  """
  @spec list_networks() :: {:ok, [map()]} | {:error, :service_unavailable}
  def list_networks do
    normalize_netmaker_error(Networks.list())
  end

  @doc """
  Returns every IPv4 and IPv6 range Netmaker currently knows about, across all
  networks (cluster networks, admin-mesh networks, and anything else).

  Used as the authoritative input to subnet-overlap checks and auto-generation:
  the local DB only knows about `cluster-*` ranges, so without this an admin
  network could collide with a generated cluster subnet and only surface at
  `create_network` time. Strict by design — propagates `:service_unavailable`
  when Netmaker is unreachable.
  """
  @spec list_network_ranges() :: {:ok, %{ipv4: [String.t()], ipv6: [String.t()]}} | {:error, :service_unavailable}
  def list_network_ranges do
    with {:ok, networks} <- list_networks() do
      {:ok,
       %{
         ipv4: networks |> Enum.map(& &1["addressrange"]) |> Enum.filter(&is_binary/1),
         ipv6: networks |> Enum.map(& &1["addressrange6"]) |> Enum.filter(&is_binary/1)
       }}
    end
  end

  @doc """
  Lists every admin cluster network in Netmaker, joined with its nodes and hosts.

  Filters Netmaker's full network list to those whose name starts with
  `"admin-cluster-"` (the convention enforced by `build_network_name/2`).
  For each, fetches the network's nodes and joins them against the global host
  list so each member carries both node-level (address, lastcheckin) and
  host-level (name, endpoint, port) detail.

  This is a raw Netmaker proxy: shapes mirror Netmaker's API and may include
  stale members. Callers in the admin domain should normalise to
  domain-friendly output (see `EdgeAdmin.Admins.list_admin_clusters/0`).

  Returns `{:ok, [%{network: net_map, members: [%{node: node, host: host}, ...]}]}`
  or `{:error, :service_unavailable}`.
  """
  @spec list_admin_cluster_networks() :: {:ok, [map()]} | {:error, :service_unavailable}
  def list_admin_cluster_networks do
    with {:ok, networks} <- list_networks(),
         {:ok, hosts} <- fetch_all_hosts() do
      hosts_by_id = Map.new(hosts, fn host -> {host["id"], host} end)

      admin_networks =
        networks
        |> Enum.filter(&admin_cluster_network?/1)
        |> Enum.sort_by(& &1["netid"])

      result =
        Enum.reduce_while(admin_networks, [], fn network, acc ->
          case list_nodes(network["netid"]) do
            {:ok, nodes} ->
              members =
                nodes
                |> Enum.map(fn node ->
                  %{node: node, host: Map.get(hosts_by_id, node["hostid"])}
                end)
                |> Enum.reject(fn %{host: host} -> is_nil(host) end)

              {:cont, [%{network: network, members: members} | acc]}

            {:error, _} = error ->
              {:halt, error}
          end
        end)

      case result do
        {:error, _} = error -> error
        list when is_list(list) -> {:ok, Enum.reverse(list)}
      end
    end
  end

  defp admin_cluster_network?(%{"netid" => netid}) when is_binary(netid) do
    String.starts_with?(netid, "admin-cluster-")
  end

  defp admin_cluster_network?(_), do: false

  @doc """
  Creates a Netmaker network.

  Returns `{:ok, network}`, `{:error, :already_exists}` if another caller created
  it concurrently (or a network with the same CIDR exists), or
  `{:error, :service_unavailable}` for other Netmaker failures.

  Netmaker reports both name collisions ("invalid network name") and CIDR
  collisions ("network cidr already in use") as 400. We map either of those
  bodies to `:already_exists` so admin replicas racing on membership startup
  can treat losers as no-ops instead of fatal errors.
  """
  @spec create_network(String.t(), map()) ::
          {:ok, map()} | {:error, :already_exists | :service_unavailable | String.t()}
  def create_network(network_name, opts \\ %{}) do
    with :ok <- validate_network_name(network_name) do
      case network_name |> Networks.create(opts) |> Api.normalize() do
        {:ok, _} = ok -> ok
        {:error, {:bad_request, body}} -> classify_create_network_400(body)
        {:error, :conflict} -> {:error, :already_exists}
        {:error, _} -> {:error, :service_unavailable}
      end
    end
  end

  # Netmaker returns 400 for both validation errors and uniqueness conflicts —
  # we recognise duplicate names/CIDRs by message body text. "invalid network
  # name" is only produced by Netmaker's IsNetworkNameUnique check; pure format
  # errors (bad chars, length) surface different messages and are pre-rejected
  # by validate_network_name/1 before we ever call Netmaker.
  @doc """
  Classifies a Netmaker `400 Bad Request` response from network creation.

  Netmaker doesn't distinguish "this CIDR is taken" from "this name is taken"
  in its status code — it returns 400 with a textual message. Both shapes
  represent races where another caller created the network first, so they
  collapse to `{:error, :already_exists}`. Anything else at 400 is treated as
  `{:error, :service_unavailable}`.

  Match strings are substring (not full-match) — they survive Netmaker
  rewording around them, but a major message change will silently fall
  through to `:service_unavailable`. Lock these down in tests.
  """
  @spec classify_create_network_400(term()) ::
          {:error, :already_exists | :service_unavailable}
  def classify_create_network_400(body) do
    message = Api.extract_message(body)

    cond do
      String.contains?(message, "network cidr already in use") -> {:error, :already_exists}
      String.contains?(message, "invalid network name") -> {:error, :already_exists}
      true -> {:error, :service_unavailable}
    end
  end

  @doc """
  Deletes a Netmaker network.

  Returns `{:ok, response}` or `{:error, :service_unavailable}`.
  """
  @spec delete_network(String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def delete_network(network_name) do
    network_name
    |> Networks.delete()
    |> normalize_netmaker_error()
  end

  @doc """
  Gets a Netmaker network.

  Returns `{:ok, network}`, `{:error, :not_found}`, or `{:error, :service_unavailable}`.
  """
  @spec get_network(String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def get_network(network_name) do
    network_name
    |> Networks.get()
    |> normalize_netmaker_error()
  end

  @doc """
  Ensures a network exists, creating it if necessary.

  Returns `:ok`, `{:error, :service_unavailable}`, or `{:error, reason}` for validation errors.

  Safe to call concurrently from multiple admin replicas: if another replica
  wins the create race, this returns `:ok` instead of failing.
  """
  def ensure_network_exists(network_name, create_opts \\ %{}) do
    case get_network(network_name) do
      {:ok, network} ->
        ensure_network_ranges_match(network_name, network, create_opts)

      {:error, :not_found} ->
        case create_network(network_name, create_opts) do
          {:ok, _} -> :ok
          {:error, :already_exists} -> :ok
          error -> error
        end

      error ->
        error
    end
  end

  defp ensure_network_ranges_match(network_name, network, opts) do
    expected_ipv4 = opts[:addressrange]
    expected_ipv6 = opts[:addressrange6]

    if (is_nil(expected_ipv4) or network["addressrange"] == expected_ipv4) and
         (is_nil(expected_ipv6) or network["addressrange6"] == expected_ipv6) do
      :ok
    else
      {:error,
       {:conflict,
        "Netmaker network #{network_name} has different immutable address ranges; recreate it before enabling dual-stack"}}
    end
  end

  @doc """
  Checks whether a Netmaker network's CIDR has room for one more node.

  Returns:
    - `:ok` — capacity available
    - `{:error, {:network_full, info}}` — no room; `info` carries `used`,
      `capacity`, and `network` so callers can log a clear diagnostic
    - `{:error, :not_found}` — network doesn't exist in Netmaker
    - `{:error, :service_unavailable}` — Netmaker can't be queried

  Capacity is computed with `usable_ipv4_capacity/1` to account for the network
  address that Netmaker's allocator (iplib) skips. We treat `used >= capacity`
  as full so the next allocation attempt is *guaranteed* to fail rather than
  *probably* fail.
  """
  @spec network_has_capacity(String.t()) ::
          :ok
          | {:error, {:network_full, %{used: non_neg_integer(), capacity: non_neg_integer(), network: String.t()}}}
          | {:error, :not_found | :service_unavailable}
  def network_has_capacity(network_name) do
    with {:ok, network} <- get_network(network_name),
         cidr when is_binary(cidr) <- network["addressrange"],
         {:ok, {_ip, prefix}} <- parse_cidr(cidr),
         {:ok, nodes} <- list_nodes(network_name) do
      capacity = usable_ipv4_capacity(prefix)
      used = length(nodes)

      if used >= capacity do
        {:error, {:network_full, %{used: used, capacity: capacity, network: network_name}}}
      else
        :ok
      end
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, :service_unavailable} -> {:error, :service_unavailable}
      _ -> {:error, :service_unavailable}
    end
  end

  @doc """
  Lists all nodes in a Netmaker network.

  Returns `{:ok, nodes}` or `{:error, :service_unavailable}`.
  """
  def list_nodes(network_name) do
    network_name
    |> Nodes.list()
    |> normalize_netmaker_error()
  end

  @doc "Reads the locally active netclient network memberships and addresses."
  @spec read_local_vpn_nodes() :: {:ok, [map()]} | {:error, term()}
  def read_local_vpn_nodes do
    Nexmaker.Cli.read_nodes()
  end

  @doc """
  Removes a host from a Netmaker network.

  Returns `{:ok, response}` or `{:error, :service_unavailable}`.
  """
  @spec remove_host_from_network(String.t(), String.t()) :: {:ok, map()} | {:error, :service_unavailable}
  def remove_host_from_network(host_id, network_name) do
    host_id
    |> Hosts.remove_from_network(network_name)
    |> normalize_netmaker_error()
  end

  @doc """
  Adds a host to a Netmaker network.

  Returns `{:ok, response}`, `{:ok, :already_joined}`, or `{:error, :service_unavailable}`.

  Netmaker returns HTTP 500 with "host already part of network" if the host already has
  a node in that network. This is treated as a success — the host is already joined and
  no further action is needed.
  """
  @spec add_host_to_network(String.t(), String.t()) ::
          {:ok, map()} | {:ok, :already_joined} | {:error, :service_unavailable}
  def add_host_to_network(host_id, network_name) do
    case host_id |> Hosts.add_to_network(network_name) |> Api.normalize() do
      {:ok, _} = ok -> ok
      {:error, :already_exists} -> {:ok, :already_joined}
      {:error, :not_found} -> {:error, :not_found}
      {:error, _} -> {:error, :service_unavailable}
    end
  end

  @doc """
  Gets the Netmaker host ID for a hostname.

  Optionally filter by network for better performance when there are many hosts.

  Returns `{:ok, host_id}`, `{:error, :host_not_found}` when listing succeeds
  but no host name matches, or `{:error, :service_unavailable}` when Netmaker
  cannot be queried. `:host_not_found` is intentionally distinct from the
  module-wide `:not_found` result.
  """
  def get_host_id(hostname, opts \\ []) do
    network_name = Keyword.get(opts, :network_name)

    Logger.debug(
      "Looking for Netmaker host with name: #{hostname}" <>
        if(network_name, do: " in network: #{network_name}", else: "")
    )

    with {:ok, hosts} <- list_hosts(),
         {:ok, nodes} <- list_nodes_for_host_resolution(network_name) do
      hosts = filter_hosts_for_host_resolution(hosts, nodes, network_name)

      Logger.debug("Retrieved #{length(hosts)} hosts from Netmaker")

      case select_host_id(hosts, nodes, hostname) do
        nil ->
          Logger.debug("No Netmaker host found with name: #{hostname}")
          {:error, :host_not_found}

        host_id ->
          Logger.debug("Found Netmaker host ID: #{host_id} for name: #{hostname}")
          {:ok, host_id}
      end
    else
      {:error, reason} ->
        Logger.error("Failed to resolve Netmaker host ID for #{hostname}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc false
  @spec select_host_id([map()], [map()], String.t()) :: String.t() | nil
  def select_host_id(hosts, nodes, hostname) do
    matching_hosts = Enum.filter(hosts, &(&1["name"] == hostname))

    case matching_hosts do
      [] ->
        nil

      [host] ->
        host["id"]

      _ ->
        node_by_host_id =
          Map.new(nodes, fn node ->
            {node["hostid"], node}
          end)

        matching_hosts
        |> Enum.max_by(
          &candidate_rank(&1, node_by_host_id),
          fn -> nil end
        )
        |> case do
          nil -> nil
          host -> host["id"]
        end
    end
  end

  defp list_nodes_for_host_resolution(nil), do: {:ok, []}
  defp list_nodes_for_host_resolution(network_name), do: list_nodes(network_name)

  defp filter_hosts_for_host_resolution(hosts, _nodes, nil), do: hosts

  defp filter_hosts_for_host_resolution(hosts, nodes, _network_name) do
    host_ids_in_network = MapSet.new(nodes, & &1["hostid"])
    Enum.filter(hosts, &MapSet.member?(host_ids_in_network, &1["id"]))
  end

  defp candidate_rank(host, node_by_host_id) do
    node = Map.get(node_by_host_id, host["id"])

    {
      if(node, do: 1, else: 0),
      if(node && node["connected"], do: 1, else: 0),
      node_timestamp(node, "lastmodified"),
      node_timestamp(node, "lastcheckin"),
      node_timestamp(node, "lastpeerupdate"),
      host["id"]
    }
  end

  defp node_timestamp(nil, _field), do: -1

  defp node_timestamp(node, field) do
    case Map.get(node, field) do
      value when is_integer(value) -> value
      _ -> -1
    end
  end

  @doc """
  Lists the global Netmaker host inventory.

  Returns `{:ok, hosts}` or `{:error, :service_unavailable}`. A successful empty
  list means Netmaker has no host records; it is not an error result.
  """
  def list_hosts do
    fetch_all_hosts()
  end

  defp fetch_all_hosts(page \\ 1, acc \\ []) do
    case normalize_netmaker_error(Hosts.list(page: page, per_page: 100)) do
      {:ok, %{"data" => hosts, "total_pages" => total_pages}} ->
        all = acc ++ hosts

        if page >= total_pages do
          {:ok, all}
        else
          fetch_all_hosts(page + 1, all)
        end

      {:ok, %{"data" => hosts}} ->
        {:ok, acc ++ hosts}

      error ->
        error
    end
  end

  @doc """
  Gets a specific Netmaker host by ID.

  Returns `{:ok, host}`, `{:error, :not_found}`, or `{:error, :service_unavailable}`.
  """
  def get_host(host_id) do
    host_id
    |> Hosts.get()
    |> normalize_netmaker_error()
  end

  @doc """
  Deletes a Netmaker host.

  Returns `{:ok, response}` or `{:error, :service_unavailable}`.
  """
  def delete_host(host_id) do
    host_id
    |> Hosts.delete()
    |> normalize_netmaker_error()
  end

  @doc """
  Force-deletes a Netmaker node by (network, node_id), routing through Netmaker's
  per-node delete endpoint instead of the host endpoint.

  Used as a defensive sweep after `delete_host/1` to remove orphan node rows
  whose `hostid` still references a host that was just deleted. Netmaker's
  `RemoveHost` iterates a cached `host.Nodes` slice and misses node rows that
  drifted out of that cache (e.g. enroll racing with delete), leaving them in
  the nodes table and visible to peer pulls.

  Returns `{:ok, response}`, `{:error, :not_found}`, or `{:error, :service_unavailable}`.
  """
  @spec delete_node(String.t(), String.t()) ::
          {:ok, map()} | {:error, :not_found | :service_unavailable}
  def delete_node(network_name, node_id) do
    network_name
    |> Nodes.delete(node_id)
    |> normalize_netmaker_error()
  end

  @doc """
  Creates an enrollment key for a Netmaker network.

  Returns `{:ok, key}` or `{:error, :service_unavailable}`.
  """
  def create_enrollment_key(network_name, opts \\ %{}) do
    network_name
    |> EnrollmentKeys.create(opts)
    |> normalize_netmaker_error()
  end

  @doc """
  Lists all enrollment keys from Netmaker.

  Returns `{:ok, keys}` or `{:error, :service_unavailable}`.
  """
  def list_enrollment_keys do
    normalize_netmaker_error(EnrollmentKeys.list())
  end

  @doc """
  Gets the default enrollment key token for a network.

  Returns `{:ok, token}` or `{:error, :default_key_not_found}`.
  """
  def get_default_enrollment_key(network_name) do
    case network_name |> EnrollmentKeys.get_default_for_network() |> Api.normalize() do
      {:ok, %{"token" => token}} when is_binary(token) and token != "" ->
        {:ok, token}

      {:ok, _} ->
        {:error, :default_key_not_found}

      {:error, _} ->
        {:error, :default_key_not_found}
    end
  end

  @doc """
  Joins an Edge VPN network using the Edge VPN CLI.

  Returns `{:ok, result}` or `{:error, reason}`.

  This is a CLI operation, not an API call, so errors are not normalized.
  """
  def join_network(opts) do
    Nexmaker.Cli.join_network(opts)
  end

  @doc """
  Checks Edge VPN CLI connection health.

  Returns `{:ok, status, info}` where status is `:healthy`, `:degraded`, or `:unhealthy`.
  """
  def edge_vpn_cli_health_check(opts \\ []) do
    Nexmaker.Cli.health_check(opts)
  end

  @doc """
  Pulls latest VPN configuration from Netmaker server.

  Forces the Edge VPN CLI to fetch full configuration via HTTP API, bypassing MQTT.
  Used by `sync_vpn_config/0` (LocalScheduler periodic backstop) — no other
  call sites today.

  Returns `:ok` or `{:error, reason}`.
  """
  def pull do
    Nexmaker.Cli.pull()
  end

  @doc """
  Pulls latest VPN config from Netmaker as a periodic consistency backstop.

  Respects the VPN_CONFIG_SYNC_ENABLED flag — no-op if disabled.
  Called by the LocalScheduler `vpn_config_sync` job (default: every 5 minutes).
  """
  def sync_vpn_config do
    if Application.get_env(:edge_admin, :vpn_config_sync_enabled, true) do
      pull()
    else
      :ok
    end
  end

  @doc """
  Checks Netmaker server health via status endpoint.

  ## Options

    - `:retries` - Number of retry attempts (default: 0)
    - `:retry_delay` - Delay between retries in milliseconds (default: 100)

  Returns `:ok` or `{:error, :service_unavailable}`.
  """
  def netmaker_health_check(opts \\ []) do
    case opts |> Nexmaker.Api.Server.status() |> normalize_netmaker_error() do
      {:ok, _status} -> :ok
      error -> error
    end
  end

  @doc """
  Checks if Netmaker superadmin exists.

  Returns `{:ok, result}` or `{:error, :service_unavailable}`.
  """
  def check_superadmin do
    normalize_netmaker_error(Superadmin.check())
  end

  @doc """
  Creates Netmaker superadmin.

  Returns `{:ok, superadmin}`, `{:error, :already_exists}` if a superadmin was
  created concurrently by another replica, or `{:error, :service_unavailable}`
  for other Netmaker failures.

  Netmaker rejects createsuperadmin with 400 + `"superadmin user already exists"`
  when one is already present; we map that to `:already_exists`.
  """
  def create_superadmin(attrs) do
    case attrs |> Superadmin.create() |> Api.normalize() do
      {:ok, _} = ok ->
        ok

      {:error, {:bad_request, body}} ->
        message = Api.extract_message(body)

        if String.contains?(message, "superadmin user already exists") do
          {:error, :already_exists}
        else
          {:error, :service_unavailable}
        end

      {:error, _} ->
        {:error, :service_unavailable}
    end
  end

  @doc """
  Creates a DNS entry in Netmaker.

  Returns `{:ok, dns_entry}` or `{:error, :service_unavailable}`.
  """
  @spec create_dns_entry(String.t(), map()) :: {:ok, map()} | {:error, :service_unavailable}
  def create_dns_entry(network_name, attrs) do
    network_name
    |> DNS.create(attrs)
    |> normalize_netmaker_error()
  end

  @doc """
  Lists all DNS entries for a network (node auto-generated + custom).

  Returns `{:ok, dns_entries}` or `{:error, :service_unavailable}`.
  """
  @spec list_dns_entries(String.t()) :: {:ok, [map()]} | {:error, :service_unavailable}
  def list_dns_entries(network_name) do
    network_name
    |> DNS.list()
    |> normalize_netmaker_error()
  end

  @doc """
  Lists only custom DNS entries for a network (excludes auto-generated node entries).

  Returns `{:ok, dns_entries}` or `{:error, :service_unavailable}`.
  """
  @spec list_custom_dns_entries(String.t()) :: {:ok, [map()]} | {:error, :service_unavailable}
  def list_custom_dns_entries(network_name) do
    network_name
    |> DNS.list_custom_entries()
    |> normalize_netmaker_error()
  end

  @doc """
  Deletes a DNS entry from Netmaker.

  Returns `{:ok, response}`, `{:error, :not_found}`, or `{:error, :service_unavailable}`.
  """
  @spec delete_dns_entry(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def delete_dns_entry(network_name, dns_name) do
    network_name
    |> DNS.delete(dns_name)
    |> normalize_netmaker_error()
  end

  @doc """
  Entry point for periodic zombie admin cleanup — called by the LocalScheduler.

  The LocalScheduler runs this on every admin instance. To reduce duplicate work,
  only the weak leader runs the actual cleanup — all other admins skip it. The weak
  leader is elected deterministically (alphabetically first admin ID in the current
  topology) so all admins independently agree on the same result without coordination.
  Duplicate work is still possible during split brain and is acceptable — cleanup
  is idempotent.

  Skipped entirely during degraded mode to avoid cascading failures.
  """
  def run_zombie_admin_cleanup do
    if Metadata.degraded?() do
      Logger.info("run_zombie_admin_cleanup: skipped — system in degraded mode")
    else
      if Metadata.am_i_weak_leader?() do
        case cleanup_zombie_admins() do
          {:ok, deleted_count} ->
            Logger.info("run_zombie_admin_cleanup: completed — #{deleted_count} host(s) deleted")

          {:error, reason} ->
            Logger.error("run_zombie_admin_cleanup: failed — #{inspect(reason)}")
        end
      else
        Logger.debug("run_zombie_admin_cleanup: skipped — not the weak leader")
      end
    end
  end

  @doc """
  Cleans up zombie admin hosts from the admin cluster.

  Deletes hosts whose nodes in the admin-cluster haven't checked in for
  the configured threshold. Protects nodes that are in our ETS metadata.

  `ZOMBIE_ADMIN_CHECKIN_THRESHOLD_MINUTES` controls the stale check-in
  threshold and defaults to 120 minutes.
  """
  @spec cleanup_zombie_admins() :: {:ok, non_neg_integer()} | {:error, term()}
  def cleanup_zombie_admins do
    admin_cluster_name = admin_cluster_name()

    threshold_minutes =
      Application.get_env(:edge_admin, :zombie_admin_checkin_threshold_minutes, 120)

    threshold_seconds = threshold_minutes * 60

    Logger.info("Starting zombie admin cleanup for #{admin_cluster_name}")
    Logger.debug("Threshold: #{threshold_minutes} minute(s) (#{threshold_seconds} seconds)")

    protected_host_ids = get_protected_host_ids()
    Logger.debug("Protected hosts: #{inspect(protected_host_ids)}")

    case list_nodes(admin_cluster_name) do
      {:ok, nodes} when is_list(nodes) ->
        delete_zombie_hosts(nodes, threshold_seconds, protected_host_ids, admin_cluster_name)

      {:ok, _} ->
        Logger.warning("Unexpected response format from Netmaker Nodes API")
        emit_zombie_cleanup_telemetry(0, :error)
        {:ok, 0}

      {:error, reason} ->
        Logger.error("Failed to query Netmaker Nodes API: #{inspect(reason)}")
        emit_zombie_cleanup_telemetry(0, :error)
        {:error, reason}
    end
  end

  defp delete_zombie_hosts(nodes, threshold_seconds, protected_host_ids, cluster_name) do
    current_time = System.system_time(:second)

    zombie_host_ids =
      nodes
      |> Enum.filter(&zombie_node?(&1, current_time, threshold_seconds, protected_host_ids))
      |> Enum.map(& &1["hostid"])
      |> Enum.uniq()

    if length(zombie_host_ids) > 0 do
      Logger.info("Found #{length(zombie_host_ids)} unique zombie host(s) to delete")
      deleted_count = Enum.reduce(zombie_host_ids, 0, &delete_zombie_host/2)
      emit_zombie_cleanup_telemetry(deleted_count, :success)
      {:ok, deleted_count}
    else
      Logger.debug("No zombie admin nodes found in #{cluster_name}")
      emit_zombie_cleanup_telemetry(0, :success)
      {:ok, 0}
    end
  end

  @doc """
  Decides whether a Netmaker node should be reaped as a zombie admin.

  A node is a zombie when its last check-in is older than `threshold_seconds`
  *and* its host is not in the protected set (current admin cluster members,
  read from syn). Protection always wins: a stale check-in on a live admin
  must not be reaped, even briefly, because the deletion takes the live admin
  off the mesh.

  Time inputs are Unix epoch seconds — `current_time` and `node["lastcheckin"]`
  must use the same units. Caller supplies both so the function stays pure.
  """
  @spec zombie_node?(map(), integer(), non_neg_integer(), [String.t()] | MapSet.t()) :: boolean()
  def zombie_node?(node, current_time, threshold_seconds, protected_host_ids) do
    age_seconds = current_time - node["lastcheckin"]
    is_zombie = age_seconds > threshold_seconds
    is_protected = node["hostid"] in protected_host_ids

    if is_zombie and not is_protected do
      Logger.debug("Zombie found: node=#{node["id"]}, host=#{node["hostid"]} (age: #{age_seconds}s)")
      true
    else
      false
    end
  end

  defp delete_zombie_host(host_id, count) do
    Logger.info("Deleting zombie admin host: #{host_id}")

    case delete_host(host_id) do
      {:ok, _} ->
        Logger.info("Successfully deleted zombie host #{host_id}")
        count + 1

      {:error, reason} ->
        Logger.error("Failed to delete host #{host_id}: #{inspect(reason)}")
        count
    end
  end

  defp emit_zombie_cleanup_telemetry(deleted_count, result) do
    :telemetry.execute(
      [:edge_admin, :vpn, :zombie_admin_cleanup],
      %{deleted_count: deleted_count},
      %{result: result}
    )
  end

  defp get_protected_host_ids do
    admin_cluster = Metadata.get_admin_cluster()

    admin_cluster
    |> Map.get(:topology, [])
    |> Enum.map(fn admin_data ->
      Map.get(admin_data, :vpn_host_id)
    end)
    |> Enum.reject(&is_nil/1)
  rescue
    _ ->
      Logger.warning("Failed to get admin_cluster metadata")
      []
  end

  @doc """
  Finds a node by host ID in a network.

  Queries the network's nodes and finds the one matching the given host_id.
  Returns the full node map so callers can access any Netmaker node property.
  """
  @spec find_node_by_host(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def find_node_by_host(network_name, host_id) do
    case list_nodes(network_name) do
      {:ok, nodes} when is_list(nodes) ->
        case Enum.find(nodes, fn node -> node["hostid"] == host_id end) do
          nil -> {:error, :not_found}
          node -> {:ok, node}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Finds a node's Netmaker node ID by host ID.

  Convenience wrapper around `find_node_by_host/2` that returns only the node ID.
  """
  @spec find_node_id_by_host(String.t(), String.t()) :: {:ok, String.t()} | {:error, :not_found | :service_unavailable}
  def find_node_id_by_host(network_name, host_id) do
    case find_node_by_host(network_name, host_id) do
      {:ok, %{"id" => node_id}} -> {:ok, node_id}
      {:error, reason} -> {:error, reason}
    end
  end
end
