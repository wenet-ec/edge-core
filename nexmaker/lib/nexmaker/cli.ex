# nexmaker/lib/nexmaker/cli.ex
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

  @doc """
  Joins a network using an enrollment token.

  First join: Registers host + creates node in network.
  Subsequent joins: Creates node in additional network (multi-cluster support).

  ## Options
    - `:token` (required) - Base64-encoded enrollment token from API response's "token" field
    - `:name` - Host name to register with (defaults to machine hostname)
    - `:endpoint` - Endpoint IP address
    - `:port` - WireGuard listen port
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
        System.cmd("netclient", ["join" | args], stderr_to_stdout: true)
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
      {:endpoint, value} -> ["--endpoint-ip", to_string(value)]
      {:port, value} -> ["--port", to_string(value)]
      {:mtu, value} -> ["--mtu", to_string(value)]
      {:interface, value} -> ["--interface", to_string(value)]
      {:static, true} -> ["--static-endpoint"]
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
    {output, exit_code} = System.cmd("netclient", ["pull"], stderr_to_stdout: true)

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
    {output, exit_code} = System.cmd("netclient", ["leave", network_name], stderr_to_stdout: true)

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
    {output, exit_code} = System.cmd("netclient", ["list"], stderr_to_stdout: true)

    case {output, exit_code} do
      {output, 0} ->
        # Use robust parser based on netclient source code
        Nexmaker.CliParser.parse_list_output(output)

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

  @nodes_json_path "/etc/netclient/nodes.json"

  @doc """
  Reads the netclient node state directly from /etc/netclient/nodes.json.

  This is the fast alternative to `list_networks/0` — no subprocess spawn,
  no geo lookup, no WireGuard interface creation. The file is maintained by
  the netclient daemon and updated on every network state change (peer joins,
  reconnects, MQTT updates from Netmaker).

  ## Returns
    - `{:ok, [network_info]}` - List of network info maps (same shape as list_networks/0)
    - `{:error, :not_found}` - nodes.json does not exist (netclient not enrolled)
    - `{:error, reason}` - Failed to read or parse the file

  ## Examples

      {:ok, networks} = Nexmaker.Cli.read_nodes()
      # => [%{"network" => "cluster-test", "connected" => true, ...}]
  """
  @spec read_nodes() :: {:ok, [map()]} | {:error, any()}
  def read_nodes do
    path = Application.get_env(:nexmaker, :nodes_json_path, @nodes_json_path)

    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, nodes_map} when is_map(nodes_map) ->
            networks =
              Enum.map(nodes_map, fn {_key, node} ->
                ip = get_in(node, ["address", "IP"]) || ""
                mask_b64 = get_in(node, ["address", "Mask"])
                ip6 = get_in(node, ["address6", "IP"]) || ""

                ipv4_addr =
                  if ip != "" && mask_b64 do
                    prefix_len =
                      mask_b64 |> Base.decode64!() |> :binary.bin_to_list() |> count_bits()

                    "#{ip}/#{prefix_len}"
                  else
                    ""
                  end

                %{
                  "network" => node["network"],
                  "node_id" => node["id"],
                  "connected" => node["connected"] == true,
                  "ipv4_addr" => ipv4_addr,
                  "ipv6_addr" => ip6
                }
              end)
              |> Enum.reject(&is_nil(&1["network"]))

            {:ok, networks}

          {:ok, _} ->
            {:ok, []}

          {:error, reason} ->
            {:error, {:json_parse_error, reason}}
        end

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Count set bits in a netmask byte list (e.g. [255, 255, 255, 0] -> 24)
  defp count_bits(bytes) when is_list(bytes) do
    Enum.reduce(bytes, 0, fn byte, acc ->
      acc + count_byte_bits(byte, 0)
    end)
  end

  defp count_byte_bits(0, acc), do: acc
  defp count_byte_bits(n, acc), do: count_byte_bits(n &&& n - 1, acc + 1)

  @doc """
  Checks whether the netmaker WireGuard interface is up at the OS level.

  Reads /proc/net/dev — the kernel's interface table. No binaries required,
  works identically in admin containers (no `wg`), agent containers (no `ip`),
  and agent on network_mode: host (shares host /proc). Ground truth: if the
  interface is registered in the kernel it appears here.

  ## Returns
    - `true` - Interface exists in the kernel
    - `false` - Interface is absent or /proc/net/dev is unreadable
  """
  @spec wireguard_interface_up?() :: boolean()
  def wireguard_interface_up? do
    case File.read("/proc/net/dev") do
      {:ok, contents} -> String.contains?(contents, "netmaker:")
      _ -> false
    end
  end

  @doc """
  Performs a fast health check on the netclient VPN connection.

  Replaces the previous `netclient list`-based approach which triggered a geo
  lookup HTTP call (ipapi.is → cloudflare → ipinfo.io) on every invocation due
  to a regression introduced in netclient v1.5.0 (NM-214).

  Instead, this reads /etc/netclient/nodes.json directly (maintained by the
  netclient daemon) and verifies the WireGuard interface is up via /proc/net/dev.

  ## Health Check Levels

  - **`:healthy`** - nodes.json has connected networks AND WireGuard interface is up
  - **`:degraded`** - nodes.json has networks but WireGuard interface is missing
    (daemon may be restarting)
  - **`:unhealthy`** - No networks in nodes.json or file doesn't exist

  ## Returns
    - `{:ok, :healthy, info}` - All checks passed
    - `{:ok, :degraded, info}` - Connected but with warnings
    - `{:ok, :unhealthy, info}` - Critical issues detected

  The `info` map contains:
    - `:networks` - List of connected network names
    - `:warnings` - List of warning messages
    - `:timestamp` - When check was performed

  ## Examples

      {:ok, :healthy, %{networks: ["cluster-test"]}} = Nexmaker.Cli.health_check()
  """
  @spec health_check(keyword()) ::
          {:ok, :healthy | :degraded | :unhealthy, map()} | {:error, any()}
  def health_check(_opts \\ []) do
    timestamp = DateTime.utc_now()

    case read_nodes() do
      {:ok, networks} when is_list(networks) and length(networks) > 0 ->
        network_names = Enum.map(networks, & &1["network"])

        if wireguard_interface_up?() do
          {:ok, :healthy,
           %{
             networks: network_names,
             warnings: [],
             timestamp: timestamp
           }}
        else
          {:ok, :degraded,
           %{
             networks: network_names,
             warnings: ["WireGuard interface netmaker is not up"],
             timestamp: timestamp
           }}
        end

      {:ok, []} ->
        {:ok, :unhealthy,
         %{
           networks: [],
           warnings: ["Not enrolled in any network (nodes.json is empty)"],
           timestamp: timestamp
         }}

      {:error, :not_found} ->
        {:ok, :unhealthy,
         %{
           networks: [],
           warnings: ["nodes.json not found — netclient not enrolled"],
           timestamp: timestamp
         }}

      {:error, reason} ->
        {:ok, :unhealthy,
         %{
           networks: [],
           warnings: ["Failed to read nodes.json: #{inspect(reason)}"],
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
        case Nexmaker.CliParser.parse_list_output(output) do
          {:ok, [network_info | _]} ->
            connected = Map.get(network_info, "connected", false)

            if connected do
              subnet = extract_subnet(Map.get(network_info, "ipv4_addr", ""))

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

          {:ok, []} ->
            {:error, :not_found}

          {:error, json_error} ->
            if String.contains?(output, "no such network") do
              {:error, :not_found}
            else
              Logger.error(
                "Failed to parse netclient output: #{inspect(json_error)}, output: #{output}"
              )

              {:error, {:json_parse_error, json_error}}
            end
        end

      {_output, _exit_code} ->
        {:error, :not_found}
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

  @doc """
  Lists detailed WireGuard peer information from the local netclient daemon.

  Returns comprehensive peer data including handshake times, traffic statistics,
  and endpoint information for all networks or a specific network.

  ## Options
    - `:network` - Filter by network name (optional)
    - `:json` - Return JSON output (default: true)

  ## Returns
    - `{:ok, peer_data}` - Map with "interface" and "peers" keys
    - `{:error, reason}` - Failed to get peer information

  ## Examples

      # List all peers across all networks
      {:ok, %{"peers" => peers}} = Nexmaker.Cli.list_peers()

      # List peers for specific network
      {:ok, data} = Nexmaker.Cli.list_peers(network: "cluster-test")
  """
  @spec list_peers(keyword()) :: {:ok, map()} | {:error, any()}
  def list_peers(opts \\ []) do
    network = Keyword.get(opts, :network)
    json = Keyword.get(opts, :json, true)

    args = build_peers_args(network, json)

    case System.cmd("netclient", ["peers" | args], stderr_to_stdout: true) do
      {output, 0} ->
        if json do
          # Use robust parser based on netclient source code
          Nexmaker.CliParser.parse_peers_output(output)
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
        "cluster-test" => [
          %{
            "network" => "cluster-test",
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
          # Use robust parser based on netclient source code
          Nexmaker.CliParser.parse_ping_output(output)
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
