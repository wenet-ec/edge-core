# edge_admin/lib/edge_admin/vpn.ex
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
  - **Error Normalization**: Consistent error handling across Netmaker API calls

  ## Key Concepts

  - **Network**: A VPN network in Netmaker (e.g., `cluster-prod`, `admin-cluster-main`)
  - **Host**: A physical/virtual machine running netclient
  - **Node**: A host's connection to a specific network
  - **DNS Name**: Short hostname (e.g., `node-abc123`, `admin-xyz789`)
  - **Hostname**: Fully qualified domain name (e.g., `node-abc123.cluster-prod.nm.internal`)
  - **Enrollment Key**: Token used to join a network

  ## Architecture

  - **Thin Wrapper**: Wraps Nexmaker API client with error normalization
  - **Stateless**: No state, all operations are direct API calls
  - **Error Handling**: Normalizes Netmaker errors to `:service_unavailable` or `:not_found`

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
      {:ok, %{}}
  """

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

    if !Regex.match?(~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/, suffix) do
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

      not Regex.match?(~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/, name) ->
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
          subnet not in existing_ranges
        end)

      _ ->
        nil
    end
  end

  @doc """
  Generates all possible subnets within a base range.
  """
  def generate_subnets({a, b, _c, _d}, base_prefix, target_prefix) do
    # Simple implementation: for /10 -> /24, generate first 256 subnets
    # This covers 100.64.0.0/24 through 100.64.255.0/24
    if target_prefix == 24 and base_prefix == 10 do
      for third_octet <- 0..255 do
        "#{a}.#{b}.#{third_octet}.0/24"
      end
    else
      # For other combinations, just return the base as-is for now
      ["#{a}.#{b}.0.0/#{target_prefix}"]
    end
  end

  # ===========================================================================
  # Netmaker API Wrappers
  # ===========================================================================

  @doc """
  Checks if a Netmaker HTTP error body indicates a "not found" condition.

  Netmaker uses HTTP 500 with specific messages for not found errors instead
  of proper 404 responses. This helper normalizes that behavior.

  ## Examples

      iex> Vpn.netmaker_not_found_error?(%{"Message" => "no result found"})
      true

      iex> Vpn.netmaker_not_found_error?("could not find any records")
      true

      iex> Vpn.netmaker_not_found_error?(%{"Message" => "internal server error"})
      false
  """
  def netmaker_not_found_error?(body) when is_binary(body) do
    String.contains?(body, "no result found") or
      String.contains?(body, "could not find any records")
  end

  def netmaker_not_found_error?(body) when is_map(body) do
    message = Map.get(body, "Message", "")

    String.contains?(message, "no result found") or
      String.contains?(message, "could not find any records")
  end

  def netmaker_not_found_error?(_), do: false

  # ===========================================================================
  # Error Normalization
  # ===========================================================================

  @doc false
  # Normalizes Netmaker API errors to standard format for context layer.
  #
  # Converts all Nexmaker errors to either:
  # - `{:error, :not_found}` - Resource not found (404 or "no result found" messages)
  # - `{:error, :service_unavailable}` - Netmaker unreachable or returned error
  #
  # This allows contexts to use clean `with` pipelines without explicit error handling.
  defp normalize_netmaker_error({:ok, result}), do: {:ok, result}

  defp normalize_netmaker_error({:error, :not_found}), do: {:error, :not_found}

  defp normalize_netmaker_error({:error, {:http_error, 500, body}}) do
    if netmaker_not_found_error?(body) do
      {:error, :not_found}
    else
      {:error, :service_unavailable}
    end
  end

  defp normalize_netmaker_error({:error, _reason}), do: {:error, :service_unavailable}

  # ===========================================================================
  # Netmaker API Wrappers
  # ===========================================================================

  @doc """
  Creates a Netmaker network.

  Returns `{:ok, network}` or `{:error, :service_unavailable}`.
  """
  @spec create_network(String.t(), map()) :: {:ok, map()} | {:error, :service_unavailable | String.t()}
  def create_network(network_name, opts \\ %{}) do
    with :ok <- validate_network_name(network_name) do
      result = Networks.create(network_name, opts)
      normalize_netmaker_error(result)
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
  """
  def ensure_network_exists(network_name, create_opts \\ %{}) do
    case get_network(network_name) do
      {:ok, _network} ->
        :ok

      {:error, :not_found} ->
        case create_network(network_name, create_opts) do
          {:ok, _} -> :ok
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Gets a node from a Netmaker network.

  Returns `{:ok, node}`, `{:error, :not_found}`, or `{:error, :service_unavailable}`.
  """
  def get_node(network_name, node_id) do
    network_name
    |> Nodes.get(node_id)
    |> normalize_netmaker_error()
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

  Returns `{:ok, response}` or `{:error, :service_unavailable}`.
  """
  @spec add_host_to_network(String.t(), String.t()) :: {:ok, map()} | {:error, :service_unavailable}
  def add_host_to_network(host_id, network_name) do
    host_id
    |> Hosts.add_to_network(network_name)
    |> normalize_netmaker_error()
  end

  @doc """
  Get the Netmaker host ID using hostname.

  Optionally filter by network for better performance when there are many hosts.

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
    with {:ok, hosts} <- normalize_netmaker_error(Hosts.list()) do
      if is_binary(network_name) do
        # Get all nodes in the network and extract their host IDs
        case list_nodes(network_name) do
          {:ok, nodes} ->
            host_ids_in_network = MapSet.new(nodes, & &1["hostid"])

            # Filter hosts that have a node in this network
            filtered_hosts =
              Enum.filter(hosts, fn host ->
                MapSet.member?(host_ids_in_network, host["id"])
              end)

            {:ok, filtered_hosts}

          error ->
            error
        end
      else
        # No filter, return all hosts
        {:ok, hosts}
      end
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
  Deletes a Netmaker host from a specific network.

  Returns `{:ok, response}` or `{:error, :service_unavailable}`.
  """
  def delete_host(network_name, host_id) do
    network_name
    |> Hosts.delete(host_id)
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
          nil -> {:error, :default_key_not_found}
          key -> {:ok, key["token"]}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes an enrollment key from Netmaker.

  Returns `{:ok, response}` or `{:error, :service_unavailable}`.
  """
  def delete_enrollment_key(key_value) do
    key_value
    |> EnrollmentKeys.delete()
    |> normalize_netmaker_error()
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
  Checks Netmaker server health via status endpoint.

  ## Options
    - `:retries` - Number of retry attempts (default: 0)
    - `:retry_delay` - Delay between retries in milliseconds (default: 100)

  Returns `:ok` or `{:error, :service_unavailable}`.
  """
  def health_check(opts \\ []) do
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

  Returns `{:ok, superadmin}` or `{:error, :service_unavailable}`.
  """
  def create_superadmin(attrs) do
    attrs
    |> Superadmin.create()
    |> normalize_netmaker_error()
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
  Lists all DNS entries for a network.

  Returns `{:ok, dns_entries}` or `{:error, :service_unavailable}`.
  """
  @spec list_dns_entries(String.t()) :: {:ok, [map()]} | {:error, :service_unavailable}
  def list_dns_entries(network_name) do
    network_name
    |> DNS.list()
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
  Cleans up zombie admin hosts from the admin cluster.

  Deletes hosts whose nodes in the admin-cluster haven't checked in for
  the configured threshold. Protects nodes that are in our ETS metadata.

  ## Configuration

  - ZOMBIE_ADMIN_CHECKIN_THRESHOLD_HOURS: Hours since last checkin (default: 2)

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

  defp zombie_node?(node, current_time, threshold_seconds, protected_host_ids) do
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
    admin_cluster = EdgeAdmin.Admins.Metadata.get_admin_cluster()

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

      iex> Vpn.find_node_by_host("cluster-default", "host-uuid-123")
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

      iex> Vpn.find_node_id_by_host("cluster-default", "host-uuid-123")
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
