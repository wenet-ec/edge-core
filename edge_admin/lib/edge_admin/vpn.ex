# edge_admin/lib/edge_admin/vpn.ex
defmodule EdgeAdmin.Vpn do
  @moduledoc """
  Centralized VPN/Netmaker utilities for Edge Admin.

  This module provides:
  - DNS hostname building
  - Network name construction and validation
  - IPv4/CIDR parsing and subnet generation
  - Netmaker API wrappers
  - Config accessors for VPN-related settings
  """

  require Logger

  # ===========================================================================
  # Config Accessors
  # ===========================================================================

  @doc """
  Returns the default Netmaker DNS domain suffix.
  Configured via NETMAKER_DEFAULT_DOMAIN (default: "nm.internal")
  """
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
  Builds a DNS hostname from components.

  ## Examples

      iex> EdgeAdmin.Vpn.build_hostname("node-abc", "cluster-xyz")
      "node-abc.cluster-xyz.nm.internal"

      iex> EdgeAdmin.Vpn.build_hostname("node-abc", "cluster-xyz", "custom.domain")
      "node-abc.cluster-xyz.custom.domain"

      iex> EdgeAdmin.Vpn.build_hostname("node-abc", "cluster-xyz", "")
      "node-abc.cluster-xyz"
  """
  def build_hostname(host, network, domain \\ nil) do
    domain = domain || default_domain()

    case domain do
      "" -> "#{host}.#{network}"
      _ -> "#{host}.#{network}.#{domain}"
    end
  end

  @doc """
  Builds a DNS domain from network name.

  ## Examples

      iex> EdgeAdmin.Vpn.build_domain("cluster-xyz")
      "cluster-xyz.nm.internal"
  """
  def build_domain(network, domain \\ nil) do
    domain = domain || default_domain()

    case domain do
      "" -> network
      _ -> "#{network}.#{domain}"
    end
  end

  # ===========================================================================
  # Network Name Construction
  # ===========================================================================

  @doc """
  Returns the Netmaker network name for an edge cluster.
  Format: cluster-{name}

  ## Examples

      iex> EdgeAdmin.Vpn.cluster_network_name("prod-east")
      "cluster-prod-east"
  """
  def cluster_network_name(cluster_name) when is_binary(cluster_name) do
    "cluster-#{cluster_name}"
  end

  @doc """
  Builds an admin name from an admin ID.
  Format: admin-{id}

  ## Examples

      iex> EdgeAdmin.Vpn.build_admin_name("k7m3n2p9x4j6")
      "admin-k7m3n2p9x4j6"
  """
  def build_admin_name(admin_id) when is_binary(admin_id) do
    "admin-#{admin_id}"
  end

  @doc """
  Builds a full admin cluster network name from a suffix.
  Format: admin-cluster-{suffix}

  Validates:
  - Suffix matches lowercase alphanumeric with hyphens
  - No leading/trailing hyphens
  - Total length <= 32 characters (Netmaker limit)

  ## Examples

      iex> EdgeAdmin.Vpn.build_admin_cluster_name("prod")
      "admin-cluster-prod"
  """
  def build_admin_cluster_name(suffix) when is_binary(suffix) do
    prefix = "admin-cluster-"
    max_total_length = 32

    # Validate format: lowercase alphanumeric with hyphens, no leading/trailing hyphens
    unless Regex.match?(~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/, suffix) do
      raise ArgumentError, """
      Admin cluster name suffix must match format: lowercase alphanumeric with hyphens, no leading/trailing hyphens
      Got: #{suffix}
      """
    end

    # Build full name
    full_name = "#{prefix}#{suffix}"

    # Validate length
    if String.length(full_name) > max_total_length do
      max_suffix_length = max_total_length - String.length(prefix)

      raise ArgumentError, """
      Admin cluster name exceeds Netmaker's #{max_total_length} character limit
      Prefix: #{prefix} (#{String.length(prefix)} chars)
      Suffix: #{suffix} (#{String.length(suffix)} chars)
      Total: #{String.length(full_name)} chars
      Max suffix length: #{max_suffix_length} chars
      """
    end

    full_name
  end

  @doc """
  Builds a node hostname from a node ID.
  Format: node-{id}

  ## Examples

      iex> EdgeAdmin.Vpn.build_node_name("a1b2c3d4-uuid")
      "node-a1b2c3d4-uuid"
  """
  def build_node_name(node_id) when is_binary(node_id) do
    "node-#{node_id}"
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
        {:error,
         "network name must be lowercase alphanumeric with hyphens, no leading/trailing hyphens"}

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
    with {:ok, {base_ip, base_prefix}} <- parse_cidr(base_cidr),
         subnets <- generate_subnets(base_ip, base_prefix, target_prefix) do
      Enum.find(subnets, fn subnet ->
        subnet not in existing_ranges
      end)
    else
      _ -> nil
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
  Creates a Netmaker network.
  """
  def create_network(network_name, opts \\ %{}) do
    case validate_network_name(network_name) do
      :ok ->
        Nexmaker.Api.Networks.create(network_name, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a Netmaker network.
  """
  def delete_network(network_name) do
    Nexmaker.Api.Networks.delete(network_name)
  end

  @doc """
  Gets a Netmaker network.
  """
  def get_network(network_name) do
    Nexmaker.Api.Networks.get(network_name)
  end

  @doc """
  Ensures a network exists, creating it if necessary.

  Returns :ok on success or {:error, reason} on failure.
  """
  def ensure_network_exists(network_name, create_opts \\ %{}) do
    case get_network(network_name) do
      {:ok, _network} ->
        :ok

      {:error, :not_found} ->
        case create_network(network_name, create_opts) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      # Netmaker returns 500 with "no result found" or "could not find any records"
      # for non-existent networks (Netmaker uses these error constants for not found)
      {:error, {:http_error, 500, body}} ->
        if String.contains?(body, "no result found") or
             String.contains?(body, "could not find any records") do
          case create_network(network_name, create_opts) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end
        else
          {:error, {:http_error, 500, body}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a node from a Netmaker network.
  """
  def get_node(network_name, node_id) do
    Nexmaker.Api.Nodes.get(network_name, node_id)
  end

  @doc """
  Lists all nodes in a Netmaker network.
  """
  def list_nodes(network_name) do
    Nexmaker.Api.Nodes.list(network_name)
  end

  @doc """
  Lists all nodes across all networks that have a specific tag.

  Queries all nodes from Netmaker and filters by the given tag.
  Each node has a `tags` field which is a list of tag strings.
  """
  def list_nodes_by_tag(tag) do
    case Nexmaker.Api.Nodes.list_all() do
      {:ok, nodes} ->
        filtered =
          Enum.filter(nodes, fn node ->
            tags = node["tags"] || []
            tag in tags
          end)

        {:ok, filtered}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Removes a host from a Netmaker network.

  ## Parameters

  - `host_id` - Netmaker host ID (UUID)
  - `network_name` - Network name to remove from

  ## Examples

      iex> Vpn.remove_host_from_network("f272e703-...", "cluster-prod")
      {:ok, %{}}
  """
  def remove_host_from_network(host_id, network_name) do
    Nexmaker.Api.Hosts.remove_from_network(host_id, network_name)
  end

  @doc """
  Adds a host to a Netmaker network.
  """
  def add_host_to_network(host_id, network_name) do
    Nexmaker.Api.Hosts.add_to_network(host_id, network_name)
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
  """
  def list_hosts(network_name \\ nil) do
    with {:ok, hosts} <- Nexmaker.Api.Hosts.list() do
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
  Deletes a Netmaker host.
  """
  def delete_host(host_id) do
    Nexmaker.Api.Hosts.delete(host_id)
  end

  @doc """
  Deletes a Netmaker host from a specific network.
  """
  def delete_host(network_name, host_id) do
    Nexmaker.Api.Hosts.delete(network_name, host_id)
  end

  @doc """
  Creates an enrollment key for a Netmaker network.
  """
  def create_enrollment_key(network_name, opts \\ %{}) do
    Nexmaker.Api.EnrollmentKeys.create(network_name, opts)
  end

  @doc """
  Lists all enrollment keys from Netmaker.
  """
  def list_enrollment_keys do
    Nexmaker.Api.EnrollmentKeys.list()
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
  """
  def delete_enrollment_key(key_value) do
    Nexmaker.Api.EnrollmentKeys.delete(key_value)
  end

  @doc """
  Joins a Netmaker network using netclient CLI.
  """
  def join_network(opts) do
    Nexmaker.Cli.join_network(opts)
  end

  @doc """
  Checks Netmaker server health via status endpoint.

  Returns :ok if server is reachable and healthy, {:error, reason} otherwise.
  """
  def health_check do
    case Nexmaker.Api.Server.status() do
      {:ok, _status} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets Netmaker server info including version.
  """
  def get_server_info do
    Nexmaker.Api.Server.get_server_info()
  end

  @doc """
  Checks if Netmaker superadmin exists.
  """
  def check_superadmin do
    Nexmaker.Api.Superadmin.check()
  end

  @doc """
  Creates Netmaker superadmin.
  """
  def create_superadmin(attrs) do
    Nexmaker.Api.Superadmin.create(attrs)
  end
end
