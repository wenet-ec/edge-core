# edge_admin/lib/edge_admin/vpn/vpn.ex
defmodule EdgeAdmin.Vpn do
  @moduledoc """
  Edge VPN operations used by Edge Admin.

  This module centralizes VPN naming, address allocation, Edge VPN operations,
  and CLI access.

  Most API calls route through `normalize_edge_vpn_error/1`, collapsing
  outcomes to `{:ok, _} | {:error, :not_found} | {:error, :service_unavailable}`.
  Functions where callers need richer outcomes document their narrower
  exceptions, such as `create_network/2`, `add_host_to_network/2`, and
  `network_has_capacity/1`.
  """

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
  Returns the default Edge VPN DNS domain suffix.
  Configured via EDGE_VPN_DEFAULT_DOMAIN (default: "nm.internal")
  """
  @spec default_domain() :: String.t()
  defdelegate default_domain(), to: VpnNaming

  @doc """
  Returns the admin cluster network name.
  Configured via :admin_cluster_name in application config.
  """
  @spec admin_cluster_name() :: String.t() | nil
  def admin_cluster_name do
    Application.get_env(:edge_admin, :admin_cluster_name)
  end

  @doc """
  Returns the number of IP slots reserved for Admin Gateway nodes.

  Should be tuned to match the total number of Admin Gateway instances across all admin clusters per core.
  """
  @spec admin_gateway_slot_reservation() :: non_neg_integer()
  def admin_gateway_slot_reservation do
    Application.get_env(:edge_admin, :admin_gateway_slot_reservation, 10)
  end

  @spec usable_ipv4_capacity(0..32) :: non_neg_integer()
  defdelegate usable_ipv4_capacity(prefix), to: VpnAddressing

  @spec build_vpn_name(String.t(), keyword()) :: String.t()
  defdelegate build_vpn_name(name, opts \\ []), to: VpnNaming

  @spec build_network_name(String.t(), keyword()) :: String.t()
  defdelegate build_network_name(name, opts \\ []), to: VpnNaming

  @spec build_vpn_domain(String.t(), String.t() | nil) :: String.t()
  defdelegate build_vpn_domain(network, domain \\ nil), to: VpnNaming

  @spec build_vpn_hostname(String.t(), String.t(), String.t() | nil) :: String.t()
  defdelegate build_vpn_hostname(host, network, domain \\ nil), to: VpnNaming

  @spec build_admin_erlang_node_name(String.t()) :: atom()
  defdelegate build_admin_erlang_node_name(hostname), to: VpnNaming

  @spec validate_network_name(String.t()) :: :ok | {:error, String.t()}
  defdelegate validate_network_name(name), to: VpnNaming

  @spec parse_cidr(String.t()) :: {:ok, tuple()} | {:error, String.t()}
  defdelegate parse_cidr(cidr), to: VpnAddressing

  @spec normalize_ipv4_cidr(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defdelegate normalize_ipv4_cidr(cidr), to: VpnAddressing

  @spec normalize_ipv4_cidr!(String.t()) :: String.t()
  defdelegate normalize_ipv4_cidr!(cidr), to: VpnAddressing

  @spec normalize_ipv4_ranges!([String.t()], keyword()) :: [String.t()]
  def normalize_ipv4_ranges!(ranges, opts \\ []) do
    VpnAddressing.normalize_ipv4_ranges!(ranges, opts)
  end

  @spec ensure_disjoint_ipv4_ranges!([String.t()]) :: [String.t()]
  defdelegate ensure_disjoint_ipv4_ranges!(ranges), to: VpnAddressing

  @spec generate_next_subnet([String.t()]) :: {:ok, String.t()} | {:error, {:conflict, String.t()}}
  defdelegate generate_next_subnet(existing_ranges \\ []), to: VpnAddressing

  @spec generate_next_ipv6_subnet([String.t()]) :: {:ok, String.t()} | {:error, {:conflict, String.t()}}
  defdelegate generate_next_ipv6_subnet(existing_ranges \\ []), to: VpnAddressing

  @spec parse_ipv6_cidr(String.t()) :: {:ok, tuple()} | {:error, String.t()}
  defdelegate parse_ipv6_cidr(cidr), to: VpnAddressing

  @spec normalize_ipv6_cidr(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defdelegate normalize_ipv6_cidr(cidr), to: VpnAddressing

  @spec normalize_ipv6_cidr!(String.t()) :: String.t()
  defdelegate normalize_ipv6_cidr!(cidr), to: VpnAddressing

  @spec normalize_ipv6_ranges!([String.t()], keyword()) :: [String.t()]
  def normalize_ipv6_ranges!(ranges, opts \\ []) do
    VpnAddressing.normalize_ipv6_ranges!(ranges, opts)
  end

  @spec ensure_disjoint_ipv6_ranges!([String.t()]) :: [String.t()]
  defdelegate ensure_disjoint_ipv6_ranges!(ranges), to: VpnAddressing

  @spec ipv6_cidrs_overlap?(String.t(), [String.t()]) :: boolean()
  defdelegate ipv6_cidrs_overlap?(cidr, existing_ranges), to: VpnAddressing

  @spec ipv4_cidrs_overlap?(String.t(), [String.t()]) :: boolean()
  defdelegate ipv4_cidrs_overlap?(cidr, existing_ranges), to: VpnAddressing

  @doc """
  Normalizes Edge VPN API responses.

  Preserves `{:ok, _}` and `{:error, :not_found}`; collapses every other error
  into `{:error, :service_unavailable}`. API calls route through
  this so callers only have to pattern-match on a small fixed set of outcomes.
  """
  @spec normalize_edge_vpn_error(term()) :: {:ok, term()} | {:error, :not_found | :service_unavailable}
  def normalize_edge_vpn_error(result) do
    case Api.normalize(result) do
      {:ok, _} = ok -> ok
      {:error, :not_found} -> {:error, :not_found}
      {:error, _} -> {:error, :service_unavailable}
    end
  end

  @doc """
  Lists all Edge VPN networks.

  Returns `{:ok, [network]}` or `{:error, :service_unavailable}`.
  Each network map includes a `"netid"` field with the network name.
  """
  @spec list_networks() :: {:ok, [map()]} | {:error, :service_unavailable}
  def list_networks do
    normalize_edge_vpn_error(Networks.list())
  end

  @doc """
  Returns every IPv4 and IPv6 range currently assigned across all
  networks (cluster networks, admin-mesh networks, and anything else).

  Used as the authoritative input to subnet-overlap checks and auto-generation:
  the local DB only knows about `cluster-*` ranges, so without this an admin
  network could collide with a generated cluster subnet and only surface at
  `create_network` time. Strict by design — propagates `:service_unavailable`
  when the Edge VPN API is unreachable.
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
  Rejects IPv4 or IPv6 ranges that overlap another network, excluding a network
  with the requested name.
  """
  @spec check_network_ranges(String.t(), map(), [map()]) :: :ok | {:error, {:conflict, String.t()}}
  def check_network_ranges(network_name, opts, networks) do
    ipv4_range = opts[:addressrange]
    ipv6_range = opts[:addressrange6]

    Enum.find_value(networks, :ok, fn network ->
      if network["netid"] == network_name do
        nil
      else
        cond do
          is_binary(ipv4_range) and
              ipv4_cidrs_overlap?(ipv4_range, Enum.filter([network["addressrange"]], &is_binary/1)) ->
            {:error,
             {:conflict,
              "IPv4 range #{ipv4_range} overlaps Edge VPN network #{network["netid"]} (#{network["addressrange"]})"}}

          is_binary(ipv6_range) and
              ipv6_cidrs_overlap?(ipv6_range, Enum.filter([network["addressrange6"]], &is_binary/1)) ->
            {:error,
             {:conflict,
              "IPv6 range #{ipv6_range} overlaps Edge VPN network #{network["netid"]} (#{network["addressrange6"]})"}}

          true ->
            nil
        end
      end
    end)
  end

  @doc """
  Lists every Admin-cluster network, joined with its nodes and hosts.

  Filters the full network list to those whose name starts with
  `"admin-cluster-"` (the convention enforced by `build_network_name/2`).
  For each, fetches the network's nodes and joins them against the global host
  list so each member carries both node-level (address, lastcheckin) and
  host-level (name, endpoint, port) detail.

  This is a raw API proxy: shapes mirror the Edge VPN API and may include
  stale members. Domain callers are responsible for converting the result to
  domain-friendly output.

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
  Creates an Edge VPN network.

  Returns `{:error, :already_exists}` for an existing network name and a
  conflict error when the requested CIDR overlaps another network.
  """
  @spec create_network(String.t(), map()) ::
          {:ok, map()}
          | {:error, :already_exists | :service_unavailable | String.t() | {:conflict, String.t()}}
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

  # The API returns 400 for both validation errors and uniqueness conflicts.
  # Duplicate names/CIDRs are recognized by message text; format errors are
  # pre-rejected by validate_network_name/1.
  @doc """
  Classifies an Edge VPN API `400 Bad Request` response from network creation.

  The API reports CIDR overlap and an existing network name as textual 400
  responses. CIDR overlap is a conflict; an existing name may be a concurrent
  creation of the expected network and is returned separately for verification.

  Matching is based on message substrings because the upstream response does
  not provide a distinct error code for these conflicts.
  """
  @spec classify_create_network_400(term()) ::
          {:error, :already_exists | :service_unavailable | {:conflict, String.t()}}
  def classify_create_network_400(body) do
    message = Api.extract_message(body)

    cond do
      String.contains?(message, "network cidr already in use") ->
        {:error, {:conflict, "network CIDR overlaps an existing Edge VPN network"}}

      String.contains?(message, "invalid network name") ->
        {:error, :already_exists}

      true ->
        {:error, :service_unavailable}
    end
  end

  @doc """
  Deletes an Edge VPN network.

  Returns `{:ok, response}` or `{:error, :service_unavailable}`.
  """
  @spec delete_network(String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def delete_network(network_name) do
    network_name
    |> Networks.delete()
    |> normalize_edge_vpn_error()
  end

  @doc """
  Gets an Edge VPN network.

  Returns `{:ok, network}`, `{:error, :not_found}`, or `{:error, :service_unavailable}`.
  """
  @spec get_network(String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def get_network(network_name) do
    network_name
    |> Networks.get()
    |> normalize_edge_vpn_error()
  end

  @doc """
  Ensures a network exists, creating it if necessary.

  Returns `:ok`, `{:error, :service_unavailable}`, or `{:error, reason}` for validation errors.

  Safe to call concurrently from multiple admin replicas: if another replica
  wins the create race, this returns `:ok` instead of failing.
  """
  @spec ensure_network_exists(String.t(), map()) ::
          :ok | {:error, String.t() | :service_unavailable | {:conflict, String.t()}}
  def ensure_network_exists(network_name, create_opts \\ %{}) do
    case get_network(network_name) do
      {:ok, network} ->
        ensure_network_ranges_match(network_name, network, create_opts)

      {:error, :not_found} ->
        with :ok <- ensure_network_ranges_available(network_name, create_opts) do
          case create_network(network_name, create_opts) do
            {:ok, _} -> :ok
            {:error, :already_exists} -> resolve_network_create_race(network_name, create_opts)
            error -> error
          end
        end

      error ->
        error
    end
  end

  defp ensure_network_ranges_available(network_name, create_opts) do
    with {:ok, networks} <- list_networks() do
      check_network_ranges(network_name, create_opts, networks)
    end
  end

  defp resolve_network_create_race(network_name, create_opts) do
    case get_network(network_name) do
      {:ok, network} ->
        ensure_network_ranges_match(network_name, network, create_opts)

      {:error, :not_found} ->
        {:error, {:conflict, "Edge VPN rejected the network CIDR because it is already in use"}}

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
        "Edge VPN network #{network_name} has different immutable address ranges; recreate it before enabling dual-stack"}}
    end
  end

  @doc """
  Checks whether an Edge VPN network's CIDR has room for one more node.

  Returns:
    - `:ok` — capacity available
    - `{:error, {:network_full, info}}` — no room; `info` carries `used`,
      `capacity`, and `network` so callers can log a clear diagnostic
    - `{:error, :not_found}` — network doesn't exist
    - `{:error, :service_unavailable}` — Edge VPN can't be queried

  Capacity is computed with `usable_ipv4_capacity/1` to account for the network
  address excluded by the Edge VPN allocator. We treat `used >= capacity`
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
  Lists all nodes in an Edge VPN network.

  Returns `{:ok, nodes}`, `{:error, :not_found}`, or
  `{:error, :service_unavailable}`.
  """
  @spec list_nodes(String.t()) :: {:ok, [map()]} | {:error, :not_found | :service_unavailable}
  def list_nodes(network_name) do
    network_name
    |> Nodes.list()
    |> normalize_edge_vpn_error()
  end

  @doc "Reads the Agent's locally active Edge VPN network memberships and addresses."
  @spec read_local_vpn_nodes() :: {:ok, [map()]} | {:error, term()}
  def read_local_vpn_nodes do
    Nexmaker.Cli.read_nodes()
  end

  @doc "Reads the locally enrolled Edge VPN host ID."
  @spec read_local_vpn_host_id() :: {:ok, String.t()} | {:error, term()}
  def read_local_vpn_host_id do
    Nexmaker.Cli.read_host_id()
  end

  @doc """
  Removes a host from an Edge VPN network.

  Returns `{:ok, response}`, `{:error, :not_found}`, or
  `{:error, :service_unavailable}`.
  """
  @spec remove_host_from_network(String.t(), String.t()) ::
          {:ok, map()} | {:error, :not_found | :service_unavailable}
  def remove_host_from_network(host_id, network_name) do
    host_id
    |> Hosts.remove_from_network(network_name)
    |> normalize_edge_vpn_error()
  end

  @doc """
  Adds a host to an Edge VPN network.

  Returns `{:ok, response}`, `{:ok, :already_joined}`, or `{:error, :service_unavailable}`.

  The API may return HTTP 500 with "host already part of network" if the host already has
  a node in that network. This is treated as a success — the host is already joined and
  no further action is needed.
  """
  @spec add_host_to_network(String.t(), String.t()) ::
          {:ok, map()} | {:ok, :already_joined} | {:error, :not_found | :service_unavailable}
  def add_host_to_network(host_id, network_name) do
    case host_id |> Hosts.add_to_network(network_name) |> Api.normalize() do
      {:ok, _} = ok -> ok
      {:error, :already_exists} -> {:ok, :already_joined}
      {:error, :not_found} -> {:error, :not_found}
      {:error, _} -> {:error, :service_unavailable}
    end
  end

  @doc """
  Gets the Edge VPN host ID for a hostname.

  Optionally filter by network for better performance when there are many hosts.

  Returns `{:ok, host_id}`, `{:error, :host_not_found}` when listing succeeds
  but no host name matches, `{:error, :not_found}` when the selected network is
  absent, or `{:error, :service_unavailable}` when Edge VPN cannot be queried.
  `:host_not_found` is distinct from a missing network.
  """
  @spec get_host_id(String.t(), keyword()) ::
          {:ok, String.t()} | {:error, :host_not_found | :not_found | :service_unavailable}
  def get_host_id(hostname, opts \\ []) do
    network_name = Keyword.get(opts, :network_name)

    Logger.debug(
      "Looking for Edge VPN host with name: #{hostname}" <>
        if(network_name, do: " in network: #{network_name}", else: "")
    )

    with {:ok, hosts} <- list_hosts(),
         {:ok, nodes} <- list_nodes_for_host_resolution(network_name) do
      hosts = filter_hosts_for_host_resolution(hosts, nodes, network_name)

      Logger.debug("Retrieved #{length(hosts)} Edge VPN hosts")

      case select_host_id(hosts, nodes, hostname) do
        nil ->
          Logger.debug("No Edge VPN host found with name: #{hostname}")
          {:error, :host_not_found}

        host_id ->
          Logger.debug("Found Edge VPN host ID: #{host_id} for name: #{hostname}")
          {:ok, host_id}
      end
    else
      {:error, reason} ->
        Logger.error("Failed to resolve Edge VPN host ID for #{hostname}: #{inspect(reason)}")
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
  Lists the global Edge VPN host inventory.

  Returns `{:ok, hosts}` or `{:error, :service_unavailable}`. A successful empty
  list means Edge VPN has no host records; it is not an error result.
  """
  @spec list_hosts() :: {:ok, [map()]} | {:error, :service_unavailable}
  def list_hosts do
    fetch_all_hosts()
  end

  defp fetch_all_hosts(page \\ 1, acc \\ []) do
    case normalize_edge_vpn_error(Hosts.list(page: page, per_page: 100)) do
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
  Gets a specific Edge VPN host by ID.

  Returns `{:ok, host}`, `{:error, :not_found}`, or `{:error, :service_unavailable}`.
  """
  @spec get_host(String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def get_host(host_id) do
    host_id
    |> Hosts.get()
    |> normalize_edge_vpn_error()
  end

  @doc """
  Deletes an Edge VPN host.

  Returns `{:ok, response}`, `{:error, :not_found}`, or
  `{:error, :service_unavailable}`.
  """
  @spec delete_host(String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def delete_host(host_id) do
    host_id
    |> Hosts.delete()
    |> normalize_edge_vpn_error()
  end

  @doc """
  Force-deletes an Edge VPN node by network and node ID.

  Returns `{:ok, response}`, `{:error, :not_found}`, or `{:error, :service_unavailable}`.
  """
  @spec delete_node(String.t(), String.t()) ::
          {:ok, map()} | {:error, :not_found | :service_unavailable}
  def delete_node(network_name, node_id) do
    case network_name |> Nodes.delete(node_id) |> Api.normalize() do
      {:error, {:bad_request, body}} -> classify_delete_node_400(body)
      result -> normalize_edge_vpn_error(result)
    end
  end

  @doc false
  @spec classify_delete_node_400(term()) :: {:error, :not_found | :service_unavailable}
  def classify_delete_node_400(body) do
    message = Api.extract_message(body)

    if String.contains?(message, "error fetching node during parameter validation: record not found") do
      {:error, :not_found}
    else
      {:error, :service_unavailable}
    end
  end

  @doc """
  Gets the default enrollment key token for a network.

  Returns `{:ok, token}` or `{:error, :default_key_not_found}`.
  """
  @spec get_default_enrollment_key(String.t()) :: {:ok, String.t()} | {:error, :default_key_not_found}
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
  @spec join_network(keyword()) :: {:ok, map()} | {:error, term()}
  def join_network(opts) do
    Nexmaker.Cli.join_network(opts)
  end

  @doc """
  Checks Edge VPN CLI connection health.

  Returns `{:ok, status, info}` where status is `:healthy`, `:degraded`, or `:unhealthy`.
  """
  @spec edge_vpn_cli_health_check(keyword()) :: {:ok, :healthy | :degraded | :unhealthy, map()}
  def edge_vpn_cli_health_check(opts \\ []) do
    Nexmaker.Cli.health_check(opts)
  end

  defp pull do
    Nexmaker.Cli.pull()
  end

  @doc """
  Pulls the latest Edge VPN configuration as a consistency backstop.

  Respects the VPN configuration pull setting; when disabled, this is a no-op.
  """
  @spec pull_vpn_config() :: :ok | {:error, term()}
  def pull_vpn_config do
    if Application.get_env(:edge_admin, :vpn_config_pull_enabled, true) do
      pull()
    else
      :ok
    end
  end

  @doc """
  Checks Edge VPN API health via its status endpoint.

  ## Options

    - `:retries` - Number of retry attempts (default: 0)
    - `:retry_delay` - Delay between retries in milliseconds (default: 100)

  Returns `:ok` or `{:error, :service_unavailable}`.
  """
  @spec edge_vpn_health_check(keyword()) :: :ok | {:error, :service_unavailable}
  def edge_vpn_health_check(opts \\ []) do
    case opts |> Nexmaker.Api.Server.status() |> normalize_edge_vpn_error() do
      {:ok, _status} -> :ok
      error -> error
    end
  end

  @doc """
  Checks whether the Edge VPN admin account exists.

  Returns `{:ok, result}` or `{:error, :service_unavailable}`.
  """
  @spec check_edge_vpn_admin_account() :: {:ok, boolean()} | {:error, :service_unavailable}
  def check_edge_vpn_admin_account do
    normalize_edge_vpn_error(Superadmin.check())
  end

  @doc """
  Creates the Edge VPN admin account.

  Returns `{:ok, account}`, `{:error, :already_exists}` if the account was
  created concurrently by another replica, or `{:error, :service_unavailable}`
  for other Edge VPN failures.

  The API rejects duplicate administrator creation with a `400` response
  when one is already present; we map that to `:already_exists`.
  """
  @spec create_edge_vpn_admin_account(map()) :: {:ok, map()} | {:error, :already_exists | :service_unavailable}
  def create_edge_vpn_admin_account(attrs) do
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
  Creates an Edge VPN DNS entry.

  Returns `{:ok, dns_entry}` or `{:error, :service_unavailable}`.
  """
  @spec create_dns_entry(String.t(), map()) :: {:ok, map()} | {:error, :service_unavailable}
  def create_dns_entry(network_name, attrs) do
    network_name
    |> DNS.create(attrs)
    |> normalize_edge_vpn_error()
  end

  @doc """
  Lists only custom DNS entries for a network (excludes auto-generated node entries).

  Returns `{:ok, dns_entries}` or `{:error, :service_unavailable}`.
  """
  @spec list_custom_dns_entries(String.t()) :: {:ok, [map()]} | {:error, :service_unavailable}
  def list_custom_dns_entries(network_name) do
    network_name
    |> DNS.list_custom_entries()
    |> normalize_edge_vpn_error()
  end

  @doc """
  Deletes an Edge VPN DNS entry.

  Returns `{:ok, response}`, `{:error, :not_found}`, or `{:error, :service_unavailable}`.
  """
  @spec delete_dns_entry(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found | :service_unavailable}
  def delete_dns_entry(network_name, dns_name) do
    network_name
    |> DNS.delete(dns_name)
    |> normalize_edge_vpn_error()
  end

  @doc """
  Finds a node by host ID in a network.

  Queries the network's nodes and finds the one matching the given host_id.
  Returns the full node map so callers can access Edge VPN node properties.
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
end
