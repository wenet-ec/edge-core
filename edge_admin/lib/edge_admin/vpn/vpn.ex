# edge_admin/lib/edge_admin/vpn/vpn.ex
defmodule EdgeAdmin.Vpn do
  @moduledoc """
  VPN integration and Netmaker API wrapper for Edge Admin.

  This module provides a centralized interface for all VPN-related operations, including:
  - **DNS/Hostname Building**: Construct DNS names and hostnames for nodes and admins
  - **Network Management**: Create, delete, and validate Netmaker networks
  - **IPv4/CIDR Utilities**: Parse and generate IP addresses and subnet ranges
  - **Host Management**: Add/remove hosts from networks, manage host lifecycle
  - **Enrollment Keys**: Create and manage network enrollment keys
  - **DNS Entries**: Create custom DNS entries for nodes (aliases)
  - **Error Normalization**: Most functions go through `normalize_netmaker_error/1`, which
    collapses to `{:ok, _} | {:error, :not_found} | {:error, :service_unavailable}`.
    Functions where the caller benefits from richer outcomes opt out and return a
    wider tuple set (e.g. `create_network/2` distinguishes `:already_exists`,
    `add_host_to_network/2` returns `:already_joined`, `network_has_capacity/1`
    returns `{:network_full, info}`).

  ## Key Concepts

  - **Network**: A VPN network in Netmaker (e.g., `cluster-prod`, `admin-cluster-a`)
  - **Host**: A physical/virtual machine running netclient
  - **Node**: A host's connection to a specific network
  - **DNS Name**: Short hostname (e.g., `node-abc123`, `admin-xyz789`)
  - **Hostname**: Fully qualified domain name (e.g., `node-abc123.cluster-prod.nm.internal`)
  - **Enrollment Key**: Token used to join a network

  ## Architecture

  - **Thin Wrapper**: Wraps Nexmaker API client with error normalization
  - **Stateless**: No state, all operations are direct API calls

  ## Examples

      # Create a network
      iex> Vpn.create_network("cluster-prod", %{addressrange: "100.64.1.0/24"})
      {:ok, %{"name" => "cluster-prod", ...}}

      # Build a VPN hostname
      iex> Vpn.build_vpn_hostname("node-abc", "cluster-prod")
      "node-abc.cluster-prod.nm.internal"

      # Get enrollment key
      iex> Vpn.get_default_enrollment_key("cluster-prod")
      {:ok, "TOKEN_VALUE"}

      # Add host to network
      iex> Vpn.add_host_to_network(host_id, "cluster-prod")
      {:ok, %{body: ""}}

      # If host is already in network (idempotent)
      iex> Vpn.add_host_to_network(host_id, "cluster-prod")
      {:ok, :already_joined}
  """

  import Bitwise

  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.Naming
  alias Nexmaker.Api
  alias Nexmaker.Api.DNS
  alias Nexmaker.Api.EnrollmentKeys
  alias Nexmaker.Api.Hosts
  alias Nexmaker.Api.Networks
  alias Nexmaker.Api.Nodes
  alias Nexmaker.Api.Superadmin

  require Logger

  # ===========================================================================
  # Config Accessors
  # ===========================================================================

  @doc """
  Returns the default Netmaker DNS domain suffix.
  Configured via NETMAKER_DEFAULT_DOMAIN (default: "nm.internal")
  """
  @spec default_domain() :: String.t()
  def default_domain do
    Application.get_env(:edge_admin, :netmaker_default_domain, "nm.internal")
  end

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
  def cluster_auto_generated_ranges do
    Application.get_env(:edge_admin, :cluster_auto_generated_ranges)
  end

  @doc """
  Returns the target subnet prefix for auto-generated clusters.
  """
  def cluster_subnet_prefix do
    Application.get_env(:edge_admin, :cluster_subnet_prefix)
  end

  @doc """
  Returns the number of IP slots reserved for admin gateway nodes.
  Should be tuned to match the total number of admin instances across all admin clusters per core.
  """
  def admin_slot_reservation do
    Application.get_env(:edge_admin, :admin_slot_reservation, 10)
  end

  @doc """
  Returns the number of IP slots reserved for node churn headroom.
  """
  def node_slot_reservation do
    Application.get_env(:edge_admin, :node_slot_reservation, 10)
  end

  # ===========================================================================
  # DNS/Hostname Building
  # ===========================================================================

  @doc """
  Builds a VPN name with a prefix.
  Format: {prefix}-{name}

  ## Options
    - `:node` - Prefix with "node-" (default)
    - `:admin` - Prefix with "admin-"

  ## Examples

      iex> EdgeAdmin.Vpn.build_vpn_name("abc123")
      "node-abc123"

      iex> EdgeAdmin.Vpn.build_vpn_name("abc123", prefix: :node)
      "node-abc123"

      iex> EdgeAdmin.Vpn.build_vpn_name("k7m3n2p9", prefix: :admin)
      "admin-k7m3n2p9"
  """
  @spec build_vpn_name(String.t(), keyword()) :: String.t()
  def build_vpn_name(name, opts \\ []) when is_binary(name) do
    prefix = Keyword.get(opts, :prefix, :node)

    case prefix do
      :node -> "node-#{name}"
      :admin -> "admin-#{name}"
    end
  end

  @doc """
  Builds a network name with a prefix.
  Format: cluster-{name} or admin-cluster-{name}

  ## Options
    - `:node` - Prefix with "cluster-" (default)
    - `:admin` - Prefix with "admin-cluster-" and validate

  ## Examples

      iex> EdgeAdmin.Vpn.build_network_name("prod-east")
      "cluster-prod-east"

      iex> EdgeAdmin.Vpn.build_network_name("prod-east", prefix: :node)
      "cluster-prod-east"

      iex> EdgeAdmin.Vpn.build_network_name("prod", prefix: :admin)
      "admin-cluster-prod"
  """
  @spec build_network_name(String.t(), keyword()) :: String.t()
  def build_network_name(name, opts \\ []) when is_binary(name) do
    prefix = Keyword.get(opts, :prefix, :node)

    case prefix do
      :node ->
        "cluster-#{name}"

      :admin ->
        validate_admin_cluster_suffix!(name)
        "admin-cluster-#{name}"
    end
  end

  @doc """
  Validates admin cluster name suffix.
  Raises ArgumentError if invalid.

  Rules:
  - Lowercase alphanumeric with hyphens
  - No leading/trailing hyphens
  - Total length with "admin-cluster-" prefix <= 32 chars
  """
  def validate_admin_cluster_suffix!(suffix) when is_binary(suffix) do
    prefix = "admin-cluster-"
    max_total_length = 32

    if !Regex.match?(Naming.cluster_name_regex(), suffix) do
      raise ArgumentError, """
      Admin cluster name suffix must match format: lowercase alphanumeric with hyphens
      Got: #{suffix}
      """
    end

    full_name = "#{prefix}#{suffix}"

    if String.length(full_name) > max_total_length do
      max_suffix_length = max_total_length - String.length(prefix)

      raise ArgumentError, """
      Admin cluster name exceeds Netmaker's #{max_total_length} character limit
      Total: #{String.length(full_name)} chars
      Max suffix length: #{max_suffix_length} chars
      """
    end

    :ok
  end

  @doc """
  Builds a VPN domain from network name.

  ## Examples

      iex> EdgeAdmin.Vpn.build_vpn_domain("cluster-xyz")
      "cluster-xyz.nm.internal"
  """
  @spec build_vpn_domain(String.t(), String.t() | nil) :: String.t()
  def build_vpn_domain(network, domain \\ nil) do
    domain = domain || default_domain()

    case domain do
      "" -> network
      _ -> "#{network}.#{domain}"
    end
  end

  @doc """
  Builds a VPN hostname from components.

  ## Examples

      iex> EdgeAdmin.Vpn.build_vpn_hostname("node-abc", "cluster-xyz")
      "node-abc.cluster-xyz.nm.internal"

      iex> EdgeAdmin.Vpn.build_vpn_hostname("node-abc", "cluster-xyz", "custom.domain")
      "node-abc.cluster-xyz.custom.domain"

      iex> EdgeAdmin.Vpn.build_vpn_hostname("node-abc", "cluster-xyz", "")
      "node-abc.cluster-xyz"
  """
  @spec build_vpn_hostname(String.t(), String.t(), String.t() | nil) :: String.t()
  def build_vpn_hostname(host, network, domain \\ nil) do
    "#{host}.#{build_vpn_domain(network, domain)}"
  end

  @doc """
  Builds an admin erlang node name from dns hostname.

  ## Examples

      iex> EdgeAdmin.Vpn.build_admin_erlang_node_name("node-abc.cluster-xyz.nm.internal")
      :"admin@node-abc.cluster-xyz.nm.internal"
  """
  def build_admin_erlang_node_name(hostname) do
    :"admin@#{hostname}"
  end

  @doc """
  Validates a network name for Netmaker compatibility.

  Returns :ok or {:error, reason}

  Validates:
  - Max 32 characters
  - Lowercase alphanumeric with hyphens
  - No leading/trailing hyphens
  """
  def validate_network_name(name) when is_binary(name) do
    cond do
      String.length(name) > 32 ->
        {:error, "network name exceeds 32 character limit"}

      not Regex.match?(Naming.cluster_name_regex(), name) ->
        {:error, "network name must be lowercase alphanumeric with hyphens, no leading/trailing hyphens"}

      true ->
        :ok
    end
  end

  # ===========================================================================
  # IPv4/CIDR Parsing
  # ===========================================================================

  @doc """
  Parses a CIDR string into IP tuple and prefix.

  ## Examples

      iex> EdgeAdmin.Vpn.parse_cidr("10.0.0.0/24")
      {:ok, {{10, 0, 0, 0}, 24}}

      iex> EdgeAdmin.Vpn.parse_cidr("invalid")
      {:error, "invalid CIDR format"}
  """
  @spec parse_cidr(String.t()) :: {:ok, {:inet.ip4_address(), 0..32}} | {:error, String.t()}
  def parse_cidr(cidr) when is_binary(cidr) do
    case String.split(cidr, "/") do
      [ip_str, prefix_str] ->
        with {:ok, ip_tuple} <- parse_ipv4(ip_str),
             {prefix, ""} <- Integer.parse(prefix_str),
             true <- prefix >= 0 and prefix <= 32 do
          {:ok, {ip_tuple, prefix}}
        else
          _ -> {:error, "invalid CIDR format"}
        end

      _ ->
        {:error, "invalid CIDR format"}
    end
  end

  @doc """
  Parses an IPv4 address string into a tuple.

  ## Examples

      iex> EdgeAdmin.Vpn.parse_ipv4("192.168.1.1")
      {:ok, {192, 168, 1, 1}}

      iex> EdgeAdmin.Vpn.parse_ipv4("invalid")
      {:error, "invalid IPv4 address"}
  """
  @spec parse_ipv4(String.t()) :: {:ok, :inet.ip4_address()} | {:error, String.t()}
  def parse_ipv4(ip_str) when is_binary(ip_str) do
    case String.split(ip_str, ".") do
      [a, b, c, d] ->
        with {a_int, ""} <- Integer.parse(a),
             {b_int, ""} <- Integer.parse(b),
             {c_int, ""} <- Integer.parse(c),
             {d_int, ""} <- Integer.parse(d),
             true <- Enum.all?([a_int, b_int, c_int, d_int], &(&1 >= 0 and &1 <= 255)) do
          {:ok, {a_int, b_int, c_int, d_int}}
        else
          _ -> {:error, "invalid IPv4 address"}
        end

      _ ->
        {:error, "invalid IPv4 address"}
    end
  end

  # ===========================================================================
  # Subnet Generation
  # ===========================================================================

  @doc """
  Generates the next available IPv4 range from configured pools.

  Uses :cluster_auto_generated_ranges and :cluster_subnet_prefix from config.
  Excludes any ranges in the provided list.

  ## Examples

      iex> EdgeAdmin.Vpn.generate_next_subnet(["100.64.0.0/24"])
      "100.64.1.0/24"
  """
  def generate_next_subnet(existing_ranges \\ []) do
    base_ranges = cluster_auto_generated_ranges()
    target_prefix = cluster_subnet_prefix()

    # Try to find available subnet from each base range
    Enum.find_value(base_ranges, fn base_range ->
      find_available_subnet(base_range, target_prefix, existing_ranges)
    end) || raise "No available IP ranges in configured pools"
  end

  @doc """
  Finds an available subnet within a base CIDR range.

  ## Examples

      iex> EdgeAdmin.Vpn.find_available_subnet("100.64.0.0/10", 24, ["100.64.0.0/24"])
      "100.64.1.0/24"
  """
  def find_available_subnet(base_cidr, target_prefix, existing_ranges) do
    case parse_cidr(base_cidr) do
      {:ok, {base_ip, base_prefix}} ->
        subnets = generate_subnets(base_ip, base_prefix, target_prefix)

        Enum.find(subnets, fn subnet ->
          not cidrs_overlap?(subnet, existing_ranges)
        end)

      _ ->
        nil
    end
  end

  @doc """
  Returns true if the given CIDR string overlaps with any range in the list.
  Overlap means one network contains the other's network address (either direction).
  """
  @spec cidrs_overlap?(String.t(), [String.t()]) :: boolean()
  def cidrs_overlap?(cidr, existing_ranges) do
    case parse_cidr(cidr) do
      {:ok, {ip, prefix}} ->
        Enum.any?(existing_ranges, fn existing ->
          case parse_cidr(existing) do
            {:ok, {ex_ip, ex_prefix}} -> cidr_intersect?({ip, prefix}, {ex_ip, ex_prefix})
            _ -> false
          end
        end)

      _ ->
        false
    end
  end

  # Two CIDRs intersect if one network address falls inside the other's range.
  defp cidr_intersect?({ip1, prefix1}, {ip2, prefix2}) do
    ip_contains?(ip1, prefix1, ip2) or ip_contains?(ip2, prefix2, ip1)
  end

  # Returns true if ip_addr falls within the network defined by net_ip/prefix.
  defp ip_contains?({a, b, c, d}, prefix, {ta, tb, tc, td}) do
    mask = prefix_to_mask(prefix)
    band(ip_to_int({a, b, c, d}), mask) == band(ip_to_int({ta, tb, tc, td}), mask)
  end

  defp ip_to_int({a, b, c, d}), do: a * 16_777_216 + b * 65_536 + c * 256 + d

  defp prefix_to_mask(0), do: 0
  defp prefix_to_mask(prefix), do: 0xFFFFFFFF |> bsl(32 - prefix) |> band(0xFFFFFFFF)

  @doc """
  Generates candidate subnets within a base range as a lazy stream.

  Works for any `base_prefix <= target_prefix` pair (e.g. `/8 → /24`,
  `/10 → /24`, `/10 → /28`, `/16 → /24`, `/24 → /24`). The base IP is realigned
  to its prefix boundary so a misaligned pool entry like `100.64.5.0/10` is
  treated as `100.64.0.0/10`.

  Returns a `Stream` because the enumeration can be large
  (`/8 → /24` = 65,536 subnets; `/10 → /28` ≈ 1M). Callers consume lazily — the
  only production caller is `find_available_subnet/3`, which stops at the first
  non-overlapping match via `Enum.find/2`.

  Raises `ArgumentError` on misconfiguration (operator-fixable, not user input):
    * `target_prefix < base_prefix` — can't carve a wider subnet from a narrower pool
    * `base_prefix` outside `0..32` or `target_prefix` outside `0..32`
  """
  @spec generate_subnets(:inet.ip4_address(), 0..32, 0..32) :: Enumerable.t(String.t())
  def generate_subnets({_, _, _, _} = base_ip, base_prefix, target_prefix)
      when is_integer(base_prefix) and is_integer(target_prefix) do
    cond do
      base_prefix < 0 or base_prefix > 32 ->
        raise ArgumentError, "base_prefix must be in 0..32, got #{base_prefix}"

      target_prefix < 0 or target_prefix > 32 ->
        raise ArgumentError, "target_prefix must be in 0..32, got #{target_prefix}"

      target_prefix < base_prefix ->
        raise ArgumentError,
              "target_prefix (#{target_prefix}) must be >= base_prefix (#{base_prefix}); " <>
                "cannot carve a wider subnet than the pool"

      true ->
        aligned_base_int = base_ip |> ip_to_int() |> band(prefix_to_mask(base_prefix))
        count = 1 <<< (target_prefix - base_prefix)
        step = 1 <<< (32 - target_prefix)

        Stream.map(0..(count - 1), fn i ->
          subnet_int = aligned_base_int + i * step
          "#{int_to_ip_string(subnet_int)}/#{target_prefix}"
        end)
    end
  end

  defp int_to_ip_string(int) do
    a = int |> bsr(24) |> band(0xFF)
    b = int |> bsr(16) |> band(0xFF)
    c = int |> bsr(8) |> band(0xFF)
    d = band(int, 0xFF)
    "#{a}.#{b}.#{c}.#{d}"
  end

  # ===========================================================================
  # Error Normalization
  # ===========================================================================

  # Delegates to Nexmaker.Api.normalize/1, then collapses anything that isn't
  # :ok / :not_found into :service_unavailable so callers get a clean two-outcome
  # contract (same behaviour as the old private normalize_netmaker_error/1).
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

  # ===========================================================================
  # Netmaker API Wrappers
  # ===========================================================================

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
  Returns every IPv4 range Netmaker currently knows about, across all networks
  (cluster networks, admin-mesh networks, and anything else).

  Used as the authoritative input to subnet-overlap checks and auto-generation:
  the local DB only knows about `cluster-*` ranges, so without this an admin
  network could collide with a generated cluster subnet and only surface at
  `create_network` time. Strict by design — propagates `:service_unavailable`
  when Netmaker is unreachable.
  """
  @spec list_network_ranges() :: {:ok, [String.t()]} | {:error, :service_unavailable}
  def list_network_ranges do
    with {:ok, networks} <- list_networks() do
      ranges =
        networks
        |> Enum.map(& &1["addressrange"])
        |> Enum.filter(&is_binary/1)

      {:ok, ranges}
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
      {:ok, _network} ->
        :ok

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

  @doc """
  Checks whether a Netmaker network's CIDR has room for one more node.

  Returns:
    - `:ok` — capacity available
    - `{:error, {:network_full, info}}` — no room; `info` carries `used`,
      `capacity`, and `network` so callers can log a clear diagnostic
    - `{:error, :not_found}` — network doesn't exist in Netmaker
    - `{:error, :service_unavailable}` — Netmaker can't be queried

  Capacity is computed as `2^(32 - prefix) - 1` to account for the network
  address that Netmaker's allocator (iplib) skips. WireGuard does not reserve
  the broadcast address, so it remains usable. We treat `used >= capacity`
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
      capacity = Integer.pow(2, 32 - prefix) - 1
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

  @doc """
  Removes a host from a Netmaker network.

  Returns `{:ok, response}` or `{:error, :service_unavailable}`.

  ## Parameters

  - `host_id` - Netmaker host ID (UUID)
  - `network_name` - Network name to remove from

  ## Examples

      iex> Vpn.remove_host_from_network("f272e703-...", "cluster-prod")
      {:ok, %{}}
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
  Get the Netmaker host ID using hostname.

  Optionally filter by network for better performance when there are many hosts.

  ## Returns

  - `{:ok, host_id}` — host found
  - `{:error, :host_not_found}` — host listing succeeded but no host had a matching
    name. Note: this atom is `:host_not_found`, not the module-wide `:not_found`,
    so callers pattern-matching on `:not_found` will miss it.
  - `{:error, :service_unavailable}` — Netmaker host listing failed

  ## Examples

      iex> Vpn.get_host_id("admin-abc123")
      {:ok, "f272e703-b48f-4b61-b4c1-bfe4fffde62b"}

      iex> Vpn.get_host_id("node-def456", network_name: "cluster-prod")
      {:ok, "a1b2c3d4-..."}
  """
  def get_host_id(hostname, opts \\ []) do
    network_name = Keyword.get(opts, :network_name)

    Logger.debug(
      "Looking for Netmaker host with name: #{hostname}" <>
        if(network_name, do: " in network: #{network_name}", else: "")
    )

    # List all hosts from Netmaker (optionally filtered by network)
    case list_hosts(network_name) do
      {:ok, hosts} ->
        Logger.debug("Retrieved #{length(hosts)} hosts from Netmaker")

        matching_host =
          Enum.find(hosts, fn host ->
            host["name"] == hostname
          end)

        case matching_host do
          nil ->
            Logger.debug("No Netmaker host found with name: #{hostname}")
            {:error, :host_not_found}

          host ->
            Logger.debug("Found Netmaker host ID: #{host["id"]} for name: #{hostname}")
            {:ok, host["id"]}
        end

      {:error, reason} ->
        Logger.error("Failed to list Netmaker hosts: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Lists Netmaker hosts, optionally filtered by network.

  When network_name is provided, lists all hosts and filters to those
  that have a node in the specified network.

  Returns `{:ok, hosts}` or `{:error, :service_unavailable}`.
  """
  def list_hosts(network_name \\ nil) do
    with {:ok, hosts} <- fetch_all_hosts() do
      if is_binary(network_name) do
        case list_nodes(network_name) do
          {:ok, nodes} ->
            host_ids_in_network = MapSet.new(nodes, & &1["hostid"])

            filtered_hosts =
              Enum.filter(hosts, fn host ->
                MapSet.member?(host_ids_in_network, host["id"])
              end)

            {:ok, filtered_hosts}

          error ->
            error
        end
      else
        {:ok, hosts}
      end
    end
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
  Gets the default enrollment key for a network.

  Netmaker automatically creates a default key (with "default": true) when a network is created.
  This key has unlimited uses and no expiration.

  Returns {:ok, token} or {:error, reason}
  """
  def get_default_enrollment_key(network_name) do
    case list_enrollment_keys() do
      {:ok, keys} ->
        # Find the default key for this network
        default_key =
          Enum.find(keys, fn key ->
            # Check if key is for this network and is the default key
            networks = Map.get(key, "networks", [])
            is_default = Map.get(key, "default", false)
            network_name in networks and is_default
          end)

        case default_key do
          nil ->
            {:error, :default_key_not_found}

          %{"token" => token} when is_binary(token) and token != "" ->
            {:ok, token}

          _ ->
            # token field is omitempty in Netmaker — absent or empty means the key
            # hasn't been tokenized yet or was returned without the field
            {:error, :default_key_not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Joins a Netmaker network using netclient CLI.

  Returns `{:ok, result}` or `{:error, reason}`.

  Note: This is a CLI operation, not an API call, so errors are not normalized.
  """
  def join_network(opts) do
    Nexmaker.Cli.join_network(opts)
  end

  @doc """
  Checks netclient VPN connection health.

  Returns `{:ok, status, info}` where status is `:healthy`, `:degraded`, or `:unhealthy`.
  """
  def netclient_health_check(opts \\ []) do
    Nexmaker.Cli.health_check(opts)
  end

  @doc """
  Pulls latest VPN configuration from Netmaker server.

  Forces netclient to fetch full configuration via HTTP API, bypassing MQTT.
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

  ## Configuration

  - ZOMBIE_ADMIN_CHECKIN_THRESHOLD_MINUTES: Minutes since last checkin (default: 120)

  ## Returns

  - `{:ok, deleted_count}` - Number of hosts deleted
  - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, 3} = Vpn.cleanup_zombie_admins()
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

  # Get protected host IDs from metadata (admin_cluster topology)
  defp get_protected_host_ids do
    admin_cluster = Metadata.get_admin_cluster()

    # Extract netmaker_host_id from each admin in topology
    # Topology structure: [%{name: "admin-abc123", netmaker_host_id: "...", ...}, ...]
    admin_cluster
    |> Map.get(:topology, [])
    |> Enum.map(fn admin_data ->
      Map.get(admin_data, :netmaker_host_id)
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
  Returns the full node map for accessing any node property (id, address, etc).

  ## Parameters
    - network_name: String - Network name
    - host_id: String - Netmaker host ID (UUID)

  ## Returns
    - `{:ok, node}` - Found node map
    - `{:error, :not_found}` - Node with this host_id not found in network
    - `{:error, :service_unavailable}` - Netmaker unavailable

  ## Examples

      iex> Vpn.find_node_by_host("cluster-test", "host-uuid-123")
      {:ok, %{"id" => "node-uuid-456", "hostid" => "host-uuid-123", "address" => "100.64.0.1/24", ...}}
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

  ## Parameters
    - network_name: String - Network name
    - host_id: String - Netmaker host ID (UUID)

  ## Returns
    - `{:ok, node_id}` - Found node ID
    - `{:error, :not_found}` - Node with this host_id not found in network
    - `{:error, :service_unavailable}` - Netmaker unavailable

  ## Examples

      iex> Vpn.find_node_id_by_host("cluster-test", "host-uuid-123")
      {:ok, "node-uuid-456"}
  """
  @spec find_node_id_by_host(String.t(), String.t()) :: {:ok, String.t()} | {:error, :not_found | :service_unavailable}
  def find_node_id_by_host(network_name, host_id) do
    case find_node_by_host(network_name, host_id) do
      {:ok, %{"id" => node_id}} -> {:ok, node_id}
      {:error, reason} -> {:error, reason}
    end
  end
end
