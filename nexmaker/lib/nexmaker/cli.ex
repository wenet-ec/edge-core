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

  require Logger

  @doc """
  Joins a network using an enrollment key or token.

  First join: Registers host + creates node in network.
  Subsequent joins: Creates node in additional network (multi-cluster support).

  ## Parameters
    - enrollment_token: String - Can be either:
      - Base64-encoded token from API response's "token" field (preferred)
      - Raw enrollment key value
    - opts: Keyword list
      - :server - Server URL with port (e.g., "netmaker:8081") to fix API token server field

  ## Returns
    - `{:ok, network_info}` - Successfully joined, returns network details
    - `{:error, reason}` - Failed to join

  ## Examples

      # Using API token field (preferred)
      {:ok, key} = Nexmaker.Api.EnrollmentKeys.create("mynet", %{tags: ["default"]})
      {:ok, network_info} = Nexmaker.Cli.join_network(key["token"], server: "netmaker:8081")

      # Using raw enrollment value
      {:ok, network_info} = Nexmaker.Cli.join_network(key["value"], server: "netmaker:8081")
  """
  @spec join_network(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def join_network(enrollment_token, opts \\ []) when is_binary(enrollment_token) do
    # Netclient v1.1.0 expects token in format: base64({"server":"host:port","value":"KEY"})
    # The API returns a "token" field that's already base64-encoded but may have wrong server
    token = case Keyword.get(opts, :server) do
      nil ->
        # Use as-is (might be pre-formatted token or raw key)
        enrollment_token

      server ->
        # Check if it's already a base64 token or raw key
        case Base.decode64(enrollment_token) do
          {:ok, json_str} ->
            # It's a base64 token - decode, fix server, re-encode
            case Jason.decode(json_str) do
              {:ok, %{"value" => value}} ->
                # Fix the server field and re-encode
                token_json = Jason.encode!(%{"server" => server, "value" => value})
                Base.encode64(token_json)
              _ ->
                # Invalid token format, treat as raw key
                token_json = Jason.encode!(%{"server" => server, "value" => enrollment_token})
                Base.encode64(token_json)
            end

          :error ->
            # Not base64, treat as raw enrollment key
            token_json = Jason.encode!(%{"server" => server, "value" => enrollment_token})
            Base.encode64(token_json)
        end
    end

    case System.cmd("netclient", ["join", "--token", token], stderr_to_stdout: true) do
      {output, 0} ->
        Logger.info("Successfully joined network via enrollment key")
        {:ok, %{output: output}}

      {output, exit_code} ->
        Logger.error("Failed to join network: #{output}")
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
    - `{:ok, network_info}` - Network info map
    - `{:error, :not_found}` - Not connected to this network

  ## Examples

      {:ok, info} = Nexmaker.Cli.check_connection("admin-cluster")
      # => %{"network" => "admin-cluster", "connected" => true, ...}
  """
  @spec check_connection(String.t()) :: {:ok, map()} | {:error, :not_found | any()}
  def check_connection(network_name) when is_binary(network_name) do
    case System.cmd("netclient", ["list", network_name], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, [network_info | _]} when is_map(network_info) ->
            {:ok, network_info}

          {:ok, []} ->
            {:error, :not_found}

          {:ok, _} ->
            {:error, :invalid_output_format}

          {:error, _reason} ->
            # Try checking if it's a "no such network" message
            if String.contains?(output, "no such network") do
              {:error, :not_found}
            else
              {:error, :invalid_output_format}
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
end
