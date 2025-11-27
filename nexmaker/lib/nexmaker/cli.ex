defmodule Nexmaker.Cli do
  @moduledoc """
  Thin Elixir wrapper around netclient CLI for VPN operations.

  This module provides functions to interact with the netclient daemon
  for network joining, leaving, and status checking.

  ## Overview

  - **Host vs Node**: Host = Physical machine (registered once), Node = Network membership
  - **Netclient daemon**: Runs as background service with auto-reconnection
  - **Resilience**: Survives network outages and system reboots automatically

  ## Examples

      # Join a network
      {:ok, network_info} = Nexmaker.Cli.join_network("nmkey-abc123...")

      # Check connection status
      {:ok, %{network: "admin-cluster", connected: true, ipv4_addr: "10.100.0.5"}} =
        Nexmaker.Cli.check_connection("admin-cluster")

      # List all networks
      {:ok, networks} = Nexmaker.Cli.list_networks()

      # Leave a network
      :ok = Nexmaker.Cli.leave_network("cluster-old-id")
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

    retry(fn -> run_netclient_join(args) end, attempts: 3)
  end

  defp run_netclient_join(args) do
    task =
      Task.async(fn ->
        System.cmd("netclient", ["join" | args], stderr_to_stdout: true)
      end)

    case Task.await(task, 20_000) do
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

  defp retry(fun, attempts: attempts) when attempts > 1 do
    case fun.() do
      {:ok, _} = ok ->
        ok

      {:error, reason} ->
        Logger.warning("Netclient join attempt failed (#{attempts} attempts remaining): #{inspect(reason)}")
        Process.sleep(500)
        retry(fun, attempts: attempts - 1)
    end
  end

  defp retry(fun, attempts: 1) do
    fun.()
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
    case System.cmd("netclient", ["leave", network_name], stderr_to_stdout: true) do
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
    case System.cmd("netclient", ["list"], stderr_to_stdout: true) do
      {output, 0} ->
        # Check for "no such network" message first (happens when exit code is 0)
        if String.contains?(output, "no such network") do
          {:ok, []}
        else
          case Jason.decode(output) do
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
  @spec check_connection(String.t()) :: {:ok, map()} | {:error, :not_found | :not_connected | any()}
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
              Logger.error("Failed to parse netclient output as JSON: #{inspect(json_error)}, output: #{output}")
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
        na = (network_int >>> 24) &&& 0xFF
        nb = (network_int >>> 16) &&& 0xFF
        nc = (network_int >>> 8) &&& 0xFF
        nd = network_int &&& 0xFF

        "#{na}.#{nb}.#{nc}.#{nd}/#{prefix}"

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp extract_subnet(_), do: nil

  # Extract JSON array from output that may contain log lines
  # Netclient sometimes outputs error logs (as JSON objects) before the actual JSON array
  defp extract_json_from_output(output) do
    # The actual data is always a JSON array starting with '['
    # Log lines are JSON objects starting with '{' on their own lines
    # We need to find the '[' that starts the array
    case :binary.match(output, "[") do
      {pos, _} -> binary_part(output, pos, byte_size(output) - pos)
      :nomatch -> output
    end
  end
end
