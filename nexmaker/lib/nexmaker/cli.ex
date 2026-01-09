defmodule Nexmaker.Cli do
  @moduledoc """
  Thin Elixir wrapper around netclient CLI for VPN operations.

  This module provides functions to interact with the netclient daemon
  for network joining, leaving, status checking, and peer diagnostics.

  ## Overview

  - **Host vs Node**: Host = Physical machine (registered once), Node = Network membership
  - **Netclient daemon**: Runs as background service with auto-reconnection
  - **Resilience**: Survives network outages and system reboots automatically

  ## Network Management

      # Join a network
      {:ok, network_info} = Nexmaker.Cli.join_network(token: "nmkey-abc123...")

      # Check connection status
      {:ok, %{network: "admin-cluster", connected: true, ipv4_addr: "10.100.0.5"}} =
        Nexmaker.Cli.check_connection("admin-cluster")

      # List all networks
      {:ok, networks} = Nexmaker.Cli.list_networks()

      # Leave a network
      :ok = Nexmaker.Cli.leave_network("cluster-old-id")

      # Get detailed peer information
      {:ok, peer_info} = Nexmaker.Cli.list_peers()
      %{"peers" => %{"admin-cluster-1" => peers}} = peer_info

      # Check peer connectivity and latency
      {:ok, results} = Nexmaker.Cli.ping_peers(network: "admin-cluster-1")
      connected_count = Enum.count(results, fn r -> r["connected"] end)
  """

  import Bitwise
  require Logger

  # Netclient config directory path
  @netclient_config_dir "/etc/netclient"

  # ===========================================================================
  # Netclient TOCTOU Bug Mitigation
  # ===========================================================================
  #
  # Netclient v1.4.0 has a TOCTOU (Time-of-check Time-of-use) race condition
  # in WriteJSONAtomic (config.go:537-604):
  #
  # 1. Directory check happens BEFORE acquiring lock (line 541-552)
  # 2. Lock acquired (line 555)
  # 3. File operations use the directory (line 561, 599)
  #
  # Race: Directory can be deleted between check and use, causing:
  # "rename /etc/netclient/netclient.json.tmp /etc/netclient/netclient.json:
  #  no such file or directory"
  #
  # Mitigation Strategy:
  # - ensure_netclient_dir/0: Pre-create directory before each netclient call
  # - run_with_retry/3: Retry on TOCTOU error (exponential backoff)
  #
  # This doesn't eliminate the race but significantly reduces occurrence.
  # ===========================================================================

  # Ensures /etc/netclient directory exists with proper permissions.
  #
  # Mitigates netclient's TOCTOU race condition by pre-creating the directory
  # right before netclient operations.
  #
  # Returns :ok always (logs error but doesn't fail if mkdir fails).
  defp ensure_netclient_dir do
    case System.cmd("mkdir", ["-p", @netclient_config_dir], stderr_to_stdout: true) do
      {_, 0} ->
        # Also ensure proper permissions
        case System.cmd("chmod", ["0775", @netclient_config_dir], stderr_to_stdout: true) do
          {_, 0} -> :ok
          {output, _} -> Logger.debug("chmod failed for #{@netclient_config_dir}: #{output}")
        end
        :ok

      {output, _exit_code} ->
        Logger.debug("mkdir failed for #{@netclient_config_dir}: #{output}")
        :ok
    end
  rescue
    _ -> :ok
  end

  # Checks if error output indicates netclient TOCTOU race condition.
  #
  # Returns true if the error message matches the netclient config directory
  # "no such file or directory" pattern.
  defp netclient_toctou_error?(output) when is_binary(output) do
    String.contains?(output, "no such file or directory") and
      String.contains?(output, @netclient_config_dir)
  end

  defp netclient_toctou_error?(_), do: false

  # Runs a netclient command with retry logic for TOCTOU errors.
  #
  # Automatically retries up to max_attempts times when the netclient TOCTOU
  # race condition is detected, with exponential backoff between attempts.
  #
  # ## Parameters
  #   - command_fn: Function that runs the netclient command (must return {output, exit_code})
  #   - max_attempts: Maximum retry attempts (default: 3)
  #   - base_delay_ms: Base delay for exponential backoff (default: 50ms)
  #
  # ## Returns
  #   - {output, exit_code} from the successful attempt or final failure
  defp run_with_retry(command_fn, max_attempts \\ 3, base_delay_ms \\ 50) do
    run_with_retry_impl(command_fn, 1, max_attempts, base_delay_ms)
  end

  defp run_with_retry_impl(command_fn, attempt, max_attempts, base_delay_ms) do
    # Ensure directory exists before each attempt
    ensure_netclient_dir()

    {output, exit_code} = command_fn.()

    # Check if we hit the TOCTOU bug and should retry
    if exit_code != 0 and netclient_toctou_error?(output) and attempt < max_attempts do
      delay_ms = base_delay_ms * :math.pow(2, attempt - 1) |> trunc()

      Logger.warning(
        "Netclient TOCTOU race condition detected (attempt #{attempt}/#{max_attempts}), " <>
          "retrying in #{delay_ms}ms..."
      )

      :timer.sleep(delay_ms)
      run_with_retry_impl(command_fn, attempt + 1, max_attempts, base_delay_ms)
    else
      {output, exit_code}
    end
  end

  @doc """
  Joins a network using an enrollment token.

  First join: Registers host + creates node in network.
  Subsequent joins: Creates node in additional network (multi-cluster support).

  ## Options
    - `:token` (required) - Base64-encoded enrollment token from API response's "token" field
    - `:name` - Host name to register with (defaults to machine hostname)
    - `:endpoint` - Endpoint IP address
    - `:mtu` - MTU value for the interface
    - `:interface` - Netmaker interface to use
    - `:static` - Flag to set host as static endpoint
    - `:static_port` - Flag to set host as static port

  ## Returns
    - `{:ok, %{}}` - Successfully joined
    - `{:error, reason}` - Failed to join

  ## Examples

      {:ok, key} = Nexmaker.Api.EnrollmentKeys.create("mynet", %{tags: ["default"]})
      {:ok, %{}} = Nexmaker.Cli.join_network(token: key["token"])

      # With custom hostname
      {:ok, %{}} = Nexmaker.Cli.join_network(token: key["token"], name: "admin-abc123")
  """
  @spec join_network(keyword()) :: {:ok, map()} | {:error, any()}
  def join_network(opts) when is_list(opts) do
    # Ensure token is provided
    _token = Keyword.fetch!(opts, :token)

    # Build args from options
    args = build_join_args(opts)

    task =
      Task.async(fn ->
        run_with_retry(fn ->
          System.cmd("netclient", ["join" | args], stderr_to_stdout: true)
        end)
      end)

    case Task.await(task, 30_000) do
      {_output, 0} ->
        {:ok, %{}}

      {output, exit_code} ->
        {:error, {:netclient_error, exit_code, output}}
    end
  rescue
    e in ErlangError ->
      Logger.error("netclient command not found or failed: #{inspect(e)}")
      {:error, :netclient_not_found}
  end

  # Build CLI arguments from keyword options
  defp build_join_args(opts) do
    opts
    |> Enum.flat_map(fn
      {:token, value} -> ["--token", value]
      {:name, value} -> ["--name", to_string(value)]
      {:endpoint, value} -> ["--endpoint", to_string(value)]
      {:mtu, value} -> ["--mtu", to_string(value)]
      {:interface, value} -> ["--interface", to_string(value)]
      {:static, true} -> ["--static"]
      {:static, false} -> []
      {:static_port, true} -> ["--static-port"]
      {:static_port, false} -> []
      _ -> []
    end)
  end

  @doc """
  Pulls latest configuration from Netmaker server.

  Forces netclient to fetch the full configuration from the server via HTTP API,
  bypassing MQTT. This ensures WireGuard interface is updated with all networks
  and addresses, useful after bulk cluster operations.

  ## Returns
    - `:ok` - Successfully pulled configuration
    - `{:error, reason}` - Failed to pull

  ## Examples

      :ok = Nexmaker.Cli.pull()
  """
  @spec pull() :: :ok | {:error, any()}
  def pull do
    {output, exit_code} =
      run_with_retry(fn ->
        System.cmd("netclient", ["pull"], stderr_to_stdout: true)
      end)

    case {output, exit_code} do
      {_output, 0} ->
        Logger.debug("Successfully pulled netclient configuration from server")
        :ok

      {output, exit_code} ->
        Logger.error("Failed to pull netclient configuration: #{output}")
        {:error, {:netclient_error, exit_code, output}}
    end
  rescue
    e in ErlangError ->
      Logger.error("netclient command not found or failed: #{inspect(e)}")
      {:error, :netclient_not_found}
  end

  @doc """
  Leaves a network.

  Deletes node from network (host remains registered).
  Used for cluster reassignment or admin rebalancing.

  ## Parameters
    - network_name: String - Network name to leave (e.g., "admin-cluster" or "cluster-abc-123")

  ## Returns
    - `:ok` - Successfully left network
    - `{:error, reason}` - Failed to leave

  ## Examples

      :ok = Nexmaker.Cli.leave_network("cluster-old-id")
  """
  @spec leave_network(String.t()) :: :ok | {:error, any()}
  def leave_network(network_name) when is_binary(network_name) do
    {output, exit_code} =
      run_with_retry(fn ->
        System.cmd("netclient", ["leave", network_name], stderr_to_stdout: true)
      end)

    case {output, exit_code} do
      {_output, 0} ->
        Logger.info("Successfully left network: #{network_name}")
        :ok

      {output, exit_code} ->
        Logger.error("Failed to leave network #{network_name}: #{output}")
        {:error, {:netclient_error, exit_code, output}}
    end
  rescue
    e in ErlangError ->
      Logger.error("netclient command not found or failed: #{inspect(e)}")
      {:error, :netclient_not_found}
  end

  @doc """
  Lists all networks this host is connected to.

  Reads from local file (nodes.json), not an API call.
  Fast, works offline, no network latency.

  ## Returns
    - `{:ok, [network_info]}` - List of network info maps
    - `{:error, reason}` - Failed to list networks

  ## Network Info Structure
      %{
        "network" => "admin-cluster",
        "node_id" => "uuid-...",
        "connected" => true,
        "ipv4_addr" => "10.100.0.5/24",
        "ipv6_addr" => ""
      }

  ## Examples

      {:ok, networks} = Nexmaker.Cli.list_networks()
      # => [%{"network" => "admin-cluster", "connected" => true, ...}]
  """
  @spec list_networks() :: {:ok, [map()]} | {:error, any()}
  def list_networks do
    {output, exit_code} =
      run_with_retry(fn ->
        System.cmd("netclient", ["list"], stderr_to_stdout: true)
      end)

    case {output, exit_code} do
      {output, 0} ->
        # Check for "no such network" message first (happens when exit code is 0)
        if String.contains?(output, "no such network") do
          {:ok, []}
        else
          # Strip error logs before JSON
          cleaned_output = extract_json_from_output(output)

          case Jason.decode(cleaned_output) do
            {:ok, networks} when is_list(networks) ->
              {:ok, networks}

            {:ok, _} ->
              {:error, :invalid_output_format}

            {:error, reason} ->
              Logger.error("Failed to parse netclient output: #{inspect(reason)}")
              {:error, {:json_parse_error, reason}}
          end
        end

      {output, exit_code} ->
        # Check if it's the "no such network" message with non-zero exit
        if String.contains?(output, "no such network") do
          {:ok, []}
        else
          Logger.error("Failed to list networks: #{output}")
          {:error, {:netclient_error, exit_code, output}}
        end
    end
  rescue
    e in ErlangError ->
      Logger.error("netclient command not found or failed: #{inspect(e)}")
      {:error, :netclient_not_found}
  end

  @doc """
  Performs a comprehensive health check on the netclient VPN connection.

  This is the recommended way to verify netclient health. It checks multiple layers:
  1. Network membership (via list_networks)
  2. WireGuard interface health (via list_peers, if peers exist)
  3. Peer handshake activity (if peers are configured)

  ## Health Check Levels

  - **`:healthy`** - All checks passed
    - Connected to at least one network
    - If peers exist, WireGuard has established handshakes

  - **`:degraded`** - Network connected but peer issues
    - On network but peers check failed (non-critical)
    - Or peers exist but no handshakes (WireGuard may have issues)

  - **`:unhealthy`** - Critical failure
    - Not connected to any network
    - Unable to determine connection status

  ## Returns
    - `{:ok, :healthy, info}` - All checks passed
    - `{:ok, :degraded, info}` - Connected but with warnings
    - `{:ok, :unhealthy, info}` - Critical issues detected
    - `{:error, reason}` - Health check failed to run

  The `info` map contains:
    - `:networks` - List of connected networks
    - `:peer_count` - Number of peers (if available)
    - `:handshake_count` - Number of peers with successful handshakes
    - `:warnings` - List of warning messages
    - `:timestamp` - When check was performed

  ## Options
    - `:skip_peers` - Skip peer health check (default: true)
    - `:require_handshakes` - Fail if no peer handshakes (default: false)

  ## Examples

      # Basic health check (fast, skips peers by default)
      {:ok, :healthy, %{networks: ["cluster-default"], peer_count: nil}} =
        Nexmaker.Cli.health_check()

      # Full health check with peer diagnostics
      {:ok, :healthy, _info} = Nexmaker.Cli.health_check(skip_peers: false)

      # Require peer handshakes (strict mode)
      {:ok, :degraded, %{warnings: ["No peer handshakes"]}} =
        Nexmaker.Cli.health_check(require_handshakes: true)
  """
  @spec health_check(keyword()) ::
          {:ok, :healthy | :degraded | :unhealthy, map()} | {:error, any()}
  def health_check(opts \\ []) do
    skip_peers = Keyword.get(opts, :skip_peers, true)
    require_handshakes = Keyword.get(opts, :require_handshakes, false)

    timestamp = DateTime.utc_now()

    # Layer 1: Check network membership (required)
    case list_networks() do
      {:ok, networks} when is_list(networks) and length(networks) > 0 ->
        # Connected to at least one network
        if skip_peers do
          {:ok, :healthy,
           %{
             networks: Enum.map(networks, & &1["network"]),
             peer_count: nil,
             handshake_count: nil,
             warnings: [],
             timestamp: timestamp
           }}
        else
          # Layer 2: Check WireGuard peer health
          check_peer_health(networks, require_handshakes, timestamp)
        end

      {:ok, []} ->
        # Not connected to any network - unhealthy
        {:ok, :unhealthy,
         %{
           networks: [],
           peer_count: nil,
           handshake_count: nil,
           warnings: ["Not connected to any network"],
           timestamp: timestamp
         }}

      {:error, reason} ->
        # Failed to determine status - unhealthy
        {:ok, :unhealthy,
         %{
           networks: [],
           peer_count: nil,
           handshake_count: nil,
           warnings: ["Failed to list networks: #{inspect(reason)}"],
           timestamp: timestamp
         }}
    end
  end

  defp check_peer_health(networks, require_handshakes, timestamp) do
    network_names = Enum.map(networks, & &1["network"])

    case list_peers() do
      {:ok, %{"peers" => peers_by_network}} when map_size(peers_by_network) > 0 ->
        # Count total peers and those with handshakes
        {total_peers, handshake_count} =
          Enum.reduce(peers_by_network, {0, 0}, fn {_network, peers}, {total, hs_count} ->
            peer_count = length(peers)

            handshakes =
              Enum.count(peers, fn peer ->
                case peer["last_handshake"] do
                  "never" -> false
                  handshake when is_binary(handshake) -> true
                  _ -> false
                end
              end)

            {total + peer_count, hs_count + handshakes}
          end)

        cond do
          handshake_count > 0 ->
            # Have peers with handshakes - healthy
            {:ok, :healthy,
             %{
               networks: network_names,
               peer_count: total_peers,
               handshake_count: handshake_count,
               warnings: [],
               timestamp: timestamp
             }}

          require_handshakes ->
            # Peers exist but no handshakes and handshakes are required - degraded
            {:ok, :degraded,
             %{
               networks: network_names,
               peer_count: total_peers,
               handshake_count: 0,
               warnings: ["Peers configured but no handshake activity"],
               timestamp: timestamp
             }}

          true ->
            # No handshakes but not required - still healthy (peers might be offline)
            {:ok, :healthy,
             %{
               networks: network_names,
               peer_count: total_peers,
               handshake_count: 0,
               warnings: ["Peers exist but no handshakes yet"],
               timestamp: timestamp
             }}
        end

      {:ok, _} ->
        # No peers yet - healthy (first/only node on network)
        {:ok, :healthy,
         %{
           networks: network_names,
           peer_count: 0,
           handshake_count: 0,
           warnings: [],
           timestamp: timestamp
         }}

      {:error, reason} ->
        # Peer check failed but we have networks - degraded
        {:ok, :degraded,
         %{
           networks: network_names,
           peer_count: nil,
           handshake_count: nil,
           warnings: ["Failed to check peers: #{inspect(reason)}"],
           timestamp: timestamp
         }}
    end
  end

  @doc """
  Checks connection status for a specific network.

  Reads from local file (nodes.json), not an API call.
  Same as list_networks/0 but filtered to one network.

  ## Parameters
    - network_name: String - Network name to check

  ## Returns
    - `{:ok, network_info}` - Network info map with subnet extracted from ipv4_addr
    - `{:error, :not_found}` - Not connected to this network
    - `{:error, :not_connected}` - Network exists but not connected yet

  ## Examples

      {:ok, info} = Nexmaker.Cli.check_connection("admin-cluster")
      # => %{network: "admin-cluster", connected: true, subnet: "100.63.0.0/24", ...}
  """
  @spec check_connection(String.t()) ::
          {:ok, map()} | {:error, :not_found | :not_connected | any()}
  def check_connection(network_name) when is_binary(network_name) do
    case System.cmd("netclient", ["list", network_name], stderr_to_stdout: true) do
      {output, 0} ->
        # Strip any log lines that appear before the JSON array
        # Netclient sometimes outputs error logs before the actual JSON
        cleaned_output = extract_json_from_output(output)

        case Jason.decode(cleaned_output) do
          {:ok, [network_info | _]} when is_map(network_info) ->
            # Check if actually connected
            connected = Map.get(network_info, "connected", false)

            if connected do
              # Extract subnet from ipv4_addr (e.g., "100.63.0.5/24" -> "100.63.0.0/24")
              subnet = extract_subnet(Map.get(network_info, "ipv4_addr", ""))

              # Convert to atom keys for easier access
              processed_info = %{
                network: Map.get(network_info, "network"),
                node_id: Map.get(network_info, "node_id"),
                connected: connected,
                ipv4_addr: Map.get(network_info, "ipv4_addr"),
                ipv6_addr: Map.get(network_info, "ipv6_addr"),
                subnet: subnet
              }

              {:ok, processed_info}
            else
              {:error, :not_connected}
            end

          {:ok, decoded} when is_map(decoded) ->
            # Single network returned as map instead of list
            connected = Map.get(decoded, "connected", false)

            if connected do
              subnet = extract_subnet(Map.get(decoded, "ipv4_addr", ""))

              processed_info = %{
                network: Map.get(decoded, "network"),
                node_id: Map.get(decoded, "node_id"),
                connected: connected,
                ipv4_addr: Map.get(decoded, "ipv4_addr"),
                ipv6_addr: Map.get(decoded, "ipv6_addr"),
                subnet: subnet
              }

              {:ok, processed_info}
            else
              {:error, :not_connected}
            end

          {:ok, []} ->
            {:error, :not_found}

          {:ok, other} ->
            Logger.error("Unexpected netclient list output format: #{inspect(other)}")
            {:error, :invalid_output_format}

          {:error, json_error} ->
            # Check if it's a "no such network" message that isn't valid JSON
            if String.contains?(output, "no such network") do
              {:error, :not_found}
            else
              Logger.error(
                "Failed to parse netclient output as JSON: #{inspect(json_error)}, output: #{output}"
              )

              {:error, {:json_parse_error, json_error}}
            end
        end

      {output, _exit_code} ->
        if String.contains?(output, "no such network") do
          {:error, :not_found}
        else
          {:error, :not_found}
        end
    end
  rescue
    e in ErlangError ->
      Logger.error("netclient command not found or failed: #{inspect(e)}")
      {:error, :netclient_not_found}
  end

  # Extract network CIDR from an IP address with CIDR notation
  # E.g., "100.63.0.5/24" -> "100.63.0.0/24"
  defp extract_subnet(ipv4_addr) when is_binary(ipv4_addr) do
    case String.split(ipv4_addr, "/") do
      [ip, prefix] ->
        # Parse IP and prefix
        octets = String.split(ip, ".") |> Enum.map(&String.to_integer/1)
        prefix_int = String.to_integer(prefix)

        # Calculate network address
        [a, b, c, d] = octets
        ip_int = (a <<< 24) + (b <<< 16) + (c <<< 8) + d

        # Apply netmask
        host_bits = 32 - prefix_int
        netmask = Bitwise.bnot((1 <<< host_bits) - 1) &&& 0xFFFFFFFF
        network_int = ip_int &&& netmask

        # Convert back to dotted notation
        na = network_int >>> 24 &&& 0xFF
        nb = network_int >>> 16 &&& 0xFF
        nc = network_int >>> 8 &&& 0xFF
        nd = network_int &&& 0xFF

        "#{na}.#{nb}.#{nc}.#{nd}/#{prefix}"

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp extract_subnet(_), do: nil

  # Extract JSON from netclient output that may contain error log lines.
  #
  # Netclient sometimes outputs error logs (JSON objects with "level" key) before
  # the actual data. This function strips those error logs and returns clean JSON.
  #
  # Strategy:
  # 1. Split output into lines
  # 2. Skip any line that looks like an error log (has "level" key)
  # 3. Find first line starting with '{' or '[' (the real data)
  # 4. Return from that point onwards (handles multi-line JSON)
  #
  # This is simpler and more robust than pattern matching on content.
  defp extract_json_from_output(output) when is_binary(output) do
    # Strategy: Remove all lines that are error logs (contain "level" key)
    # Keep all other lines intact (including lines that start mid-JSON)
    lines = String.split(output, "\n")

    # Filter out error log lines
    clean_lines =
      Enum.reject(lines, fn line ->
        # Skip empty lines and error logs
        trimmed = String.trim(line)
        trimmed == "" or String.contains?(line, "\"level\"")
      end)

    # Rejoin the remaining lines
    Enum.join(clean_lines, "\n")
  end

  @doc """
  Lists WireGuard peer information including public keys, endpoints, traffic stats, and more.

  Returns detailed peer information from the WireGuard interface with data enriched from
  the Netmaker server (hostnames, network associations, etc.).

  ## Options
    - `:network` - Filter peers by network name (optional)
    - `:json` - Return raw JSON output (default: true for programmatic access)

  ## Returns
    - `{:ok, peer_info}` - Peer information map
    - `{:error, reason}` - Failed to get peer information

  ## Peer Info Structure (when json: true)
      %{
        "interface" => %{
          "name" => "netmaker",
          "port" => 51821,
          "public_key" => "abc123..."
        },
        "peers" => %{
          "admin-cluster-1" => [
            %{
              "public_key" => "xyz789...",
              "host_name" => "admin-abc123",
              "network" => "admin-cluster-1",
              "endpoint" => "192.168.1.5:51821",
              "last_handshake" => "2 minutes ago",
              "last_handshake_time" => "2025-12-25T08:00:00Z",
              "receive_bytes" => 1024000,
              "transmit_bytes" => 2048000,
              "allowed_ips" => ["100.63.0.1/32"],
              "is_extclient" => false,
              "username" => ""
            }
          ],
          "cluster-default" => [...]
        }
      }

  ## Examples

      # Get all peers across all networks
      {:ok, peer_info} = Nexmaker.Cli.list_peers()

      # Get peers for specific network
      {:ok, peer_info} = Nexmaker.Cli.list_peers(network: "admin-cluster-1")

      # Access interface info
      %{"interface" => %{"name" => iface}} = peer_info

      # Access peers by network
      admin_peers = peer_info["peers"]["admin-cluster-1"]
  """
  @spec list_peers(keyword()) :: {:ok, map()} | {:error, any()}
  def list_peers(opts \\ []) do
    network = Keyword.get(opts, :network)
    json = Keyword.get(opts, :json, true)

    args = build_peers_args(network, json)

    case System.cmd("netclient", ["peers" | args], stderr_to_stdout: true) do
      {output, 0} ->
        if json do
          # Extract JSON from output (skip any error logs)
          cleaned_output = extract_json_from_output(output)

          case Jason.decode(cleaned_output) do
            {:ok, peer_data} when is_map(peer_data) ->
              {:ok, peer_data}

            {:ok, []} ->
              # Empty array means no peers - return empty peer map structure
              Logger.warning("netclient peers returned empty array (no peers found)")
              {:ok, %{"peers" => %{}}}

            {:ok, other} ->
              Logger.error("netclient peers returned unexpected JSON format (expected map, got #{inspect(other)})")
              Logger.debug("Raw output: #{output}")
              Logger.debug("Cleaned output: #{cleaned_output}")
              {:error, :invalid_output_format}

            {:error, reason} ->
              Logger.error("Failed to parse netclient peers output: #{inspect(reason)}")
              Logger.debug("Raw output: #{output}")
              Logger.debug("Cleaned output: #{cleaned_output}")
              {:error, {:json_parse_error, reason}}
          end
        else
          # Return raw text output
          {:ok, output}
        end

      {output, exit_code} ->
        Logger.error("Failed to get peer information: #{output}")
        {:error, {:netclient_error, exit_code, output}}
    end
  rescue
    e in ErlangError ->
      Logger.error("netclient command not found or failed: #{inspect(e)}")
      {:error, :netclient_not_found}
  end

  defp build_peers_args(network, json) do
    args = []
    args = if network, do: args ++ [network], else: args
    args = if json, do: args ++ ["-j"], else: args
    args
  end

  @doc """
  Checks connectivity and latency to WireGuard peers across networks.

  Pings peers through the WireGuard VPN tunnel and measures latency.
  Useful for diagnosing network connectivity issues and monitoring peer health.

  ## Options
    - `:network` - Filter by network name (optional)
    - `:peer` - Filter by peer name, address, or ID (case-insensitive, optional)
    - `:count` - Number of ping packets to send per peer (default: 3)
    - `:ipv4` - Use IPv4 addresses only (default: false)
    - `:ipv6` - Use IPv6 addresses only (default: false)
    - `:json` - Return JSON output (default: true)

  ## Returns
    - `{:ok, ping_results}` - Map of network name to list of ping results
    - `{:error, reason}` - Failed to ping peers

  ## Ping Result Structure (when json: true)
      %{
        "cluster-default" => [
          %{
            "network" => "cluster-default",
            "name" => "admin-abc123",
            "address" => "100.64.0.4",
            "is_extclient" => false,
            "connected" => true,
            "latency_ms" => 0,
            "username" => ""
          }
        ],
        "admin-cluster-1" => [...]
      }

  ## Examples

      # Ping all peers on all networks
      {:ok, results} = Nexmaker.Cli.ping_peers()

      # Ping peers on specific network
      {:ok, results} = Nexmaker.Cli.ping_peers(network: "admin-cluster-1")

      # Ping specific peer
      {:ok, results} = Nexmaker.Cli.ping_peers(peer: "admin-abc123")

      # Ping with more packets for accuracy
      {:ok, results} = Nexmaker.Cli.ping_peers(count: 10)

      # Check connectivity status
      connected_peers = Enum.filter(results, fn r -> r["connected"] end)
      avg_latency = Enum.reduce(connected_peers, 0, fn r, acc -> acc + r["latency_ms"] end) / length(connected_peers)
  """
  @spec ping_peers(keyword()) :: {:ok, map()} | {:error, any()}
  def ping_peers(opts \\ []) do
    network = Keyword.get(opts, :network)
    peer = Keyword.get(opts, :peer)
    count = Keyword.get(opts, :count, 3)
    ipv4 = Keyword.get(opts, :ipv4, false)
    ipv6 = Keyword.get(opts, :ipv6, false)
    json = Keyword.get(opts, :json, true)

    args = build_ping_args(network, peer, count, ipv4, ipv6, json)

    case System.cmd("netclient", ["ping" | args], stderr_to_stdout: true) do
      {output, 0} ->
        if json do
          # Extract JSON from output (skip any error logs)
          cleaned_output = extract_json_from_output(output)

          case Jason.decode(cleaned_output) do
            {:ok, ping_results} when is_map(ping_results) ->
              {:ok, ping_results}

            {:ok, _other} ->
              {:error, :invalid_output_format}

            {:error, reason} ->
              Logger.error("Failed to parse netclient ping output: #{inspect(reason)}")
              {:error, {:json_parse_error, reason}}
          end
        else
          # Return raw text output
          {:ok, output}
        end

      {output, exit_code} ->
        Logger.error("Failed to ping peers: #{output}")
        {:error, {:netclient_error, exit_code, output}}
    end
  rescue
    e in ErlangError ->
      Logger.error("netclient command not found or failed: #{inspect(e)}")
      {:error, :netclient_not_found}
  end

  defp build_ping_args(network, peer, count, ipv4, ipv6, json) do
    args = []
    args = if network, do: args ++ ["-n", network], else: args
    args = if peer, do: args ++ ["-p", peer], else: args
    args = if count, do: args ++ ["-c", to_string(count)], else: args
    args = if ipv4, do: args ++ ["-4"], else: args
    args = if ipv6, do: args ++ ["-6"], else: args
    args = if json, do: args ++ ["-j"], else: args
    args
  end
end
