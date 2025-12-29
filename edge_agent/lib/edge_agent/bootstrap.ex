# edge_agent/lib/edge_agent/bootstrap.ex
defmodule EdgeAgent.Bootstrap do
  @moduledoc """
  One-time bootstrap orchestrator for edge agent startup.

  This GenServer runs exactly once during application startup and performs critical
  initialization tasks to establish agent identity, join the VPN network, discover
  and register with admin servers, and sync pending commands.

  ## Key Concepts

  - **Node Identity**: Persistent or random UUID identifying this agent
  - **VPN Join**: Connects to cluster network via Netmaker enrollment token
  - **Admin Discovery**: Finds admin servers via Netmaker API (no hardcoded addresses)
  - **Registration**: Registers node with admin and receives API token
  - **Command Sync**: Downloads pending command executions from admin

  ## Responsibilities

  1. **Identity Determination**
     - Try persistent system ID (machine-id, hardware UUID)
     - Fall back to random UUID if persistent ID unavailable
     - Store identity in Settings database for persistence

  2. **VPN Network Join**
     - Join edge cluster network using enrollment token
     - Verify netclient connection and health
     - Obtain VPN IP address for communication

  3. **Admin Discovery**
     - Query Netmaker for hosts in admin cluster network
     - Extract admin URLs from host metadata
     - Validate at least one admin is available (fail fast)

  4. **Node Registration**
     - Send registration payload to admin API
     - Receive API token for authentication
     - Receive proxy password for proxy server authentication
     - Store credentials in Settings

  5. **Command Sync**
     - Download pending command executions from admin
     - Store in local database and enqueue for execution
     - Handle duplicates gracefully

  ## Bootstrap Sequence

  ```
  1. Determine node identity (persistent → random)
  2. Join VPN network via enrollment token
  3. Discover admin URLs from Netmaker API
  4. Register with admin and receive credentials
  5. Sync pending command executions
  ```

  ## Failure Handling

  Bootstrap failures are **FATAL** and crash the supervision tree:
  - Identity determination failure → Can't identify node
  - VPN join failure → Can't communicate with admins
  - Admin discovery failure → No admin servers available
  - Registration failure → Can't authenticate with admin

  Command sync failures are **NON-FATAL** (logged as warning, bootstrap continues).

  ## Configuration

  All values read from Application config (set in runtime.exs):
  - `:enrollment_key` - Netmaker enrollment token
  - `:run_bootstrap` - Whether to run bootstrap (default: true)
  - `:use_random_id` - Force random UUID instead of persistent ID
  - `:http_port` - Agent HTTP API port (default: 44000)
  - `:ssh_port` - Agent SSH server port (default: 40022)
  - `:host_metrics_port` - Node exporter port (default: 49100)
  - `:wireguard_metrics_port` - WireGuard exporter port (default: 49586)
  - `:http_proxy_port` - HTTP proxy port (default: 43128)
  - `:socks5_proxy_port` - SOCKS5 proxy port (default: 41080)

  ## Examples

      # Bootstrap runs automatically on application start
      # Success: Application continues
      # Failure: Application crashes with detailed error

      # Check if bootstrap completed
      iex> Bootstrap.initialized?()
      true

      # Skip bootstrap in test environment
      config :edge_agent, run_bootstrap: false
  """

  use GenServer

  alias EdgeAgent.Commands
  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.EdgeClusters.Discovery
  alias EdgeAgent.Identity
  alias EdgeAgent.Settings
  alias EdgeAgent.Vpn

  require Logger

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Starts the Bootstrap GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns true if bootstrap completed successfully.
  Used by health checks.
  """
  @spec initialized?() :: boolean()
  def initialized? do
    case Process.whereis(__MODULE__) do
      nil ->
        false

      pid ->
        try do
          GenServer.call(pid, :initialized?, 1000)
        catch
          :exit, _ -> false
        end
    end
  end

  # =============================================================================
  # GenServer Callbacks
  # =============================================================================

  @impl true
  def init(_opts) do
    if Application.get_env(:edge_agent, :run_bootstrap, true) do
      Logger.info("Bootstrap starting...")

      case do_bootstrap() do
        :ok ->
          Logger.info("Bootstrap completed successfully")
          {:ok, %{status: :complete, initialized: true}}

        {:error, reason} ->
          Logger.error("Bootstrap failed: #{inspect(reason)}")
          {:stop, reason}
      end
    else
      Logger.info("Bootstrap skipped (disabled in config or test environment)")
      {:ok, %{status: :skipped, initialized: false}}
    end
  end

  @impl true
  def handle_call(:initialized?, _from, state) do
    {:reply, Map.get(state, :initialized, false), state}
  end

  # =============================================================================
  # Bootstrap Flow
  # =============================================================================

  defp do_bootstrap do
    with {:ok, node_id, id_type} <- step_1_determine_identity(),
         :ok <- step_2_join_vpn(node_id),
         {:ok, network_name, _admin_urls} <- step_3_discover_admins(),
         :ok <- step_4_register_node(node_id, id_type, network_name),
         :ok <- step_5_get_sent_command_executions(node_id) do
      Logger.info("All bootstrap steps completed")
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Bootstrap step failed: #{inspect(reason)}")
        error
    end
  end

  # =============================================================================
  # Step 1: Determine Identity
  # =============================================================================

  defp step_1_determine_identity do
    Logger.info("Step 1: Determining node identity...")

    case Identity.determine() do
      {:ok, node_id, id_type} ->
        Logger.info("Node identity: #{String.slice(node_id, 0, 8)}... (#{id_type})")

        # Store identity in settings for persistence across restarts
        Settings.set_node_id(node_id)
        Settings.set_id_type(id_type)

        {:ok, node_id, id_type}

      {:error, reason} ->
        {:error, "Failed to determine node identity: #{inspect(reason)}"}
    end
  end

  # =============================================================================
  # Step 2: Join VPN
  # =============================================================================

  defp step_2_join_vpn(node_id) do
    Logger.info("Step 2: Joining VPN network...")
    Vpn.join_if_needed(node_id)
  end

  # =============================================================================
  # Step 3: Discover Admins
  # =============================================================================

  defp step_3_discover_admins do
    Logger.info("Step 3: Discovering admins...")

    # Bootstrap requires at least one admin to be discovered (fail fast)
    result =
      case Discovery.discover_admins(fail_on_empty: true) do
        {:ok, network_name, admin_urls} ->
          Logger.info("Network: #{network_name}")
          Logger.info("Discovered #{length(admin_urls)} admin(s)")
          {:ok, network_name, admin_urls}

        {:error, reason} ->
          {:error, "Admin discovery failed: #{inspect(reason)}"}
      end

    status =
      case result do
        {:ok, _, _} -> :success
        {:error, _} -> :failure
      end

    :telemetry.execute(
      [:edge_agent, :discovery, :admin, :found],
      %{count: 1, total: 1},
      %{status: status}
    )

    result
  end

  # =============================================================================
  # Step 4: Register Node
  # =============================================================================

  defp step_4_register_node(node_id, id_type, network_name) do
    Logger.info("Step 4: Registering with admin...")

    start_time = System.monotonic_time(:millisecond)
    payload = build_registration_payload(node_id, id_type, network_name)

    result =
      case AdminClient.register_node(payload) do
        {:ok, node_data} ->
          # Store API token and proxy password from registration response
          api_token = node_data["api_token"]
          proxy_password = node_data["proxy_password"]

          cond do
            is_nil(api_token) ->
              {:error, "Registration response missing api_token"}

            is_nil(proxy_password) ->
              {:error, "Registration response missing proxy_password"}

            true ->
              Settings.set_api_token(api_token)
              Settings.set_proxy_password(proxy_password)
              Logger.info("Successfully registered with admin")
              :ok
          end

        {:error, reason} ->
          {:error, "Registration failed: #{inspect(reason)}"}
      end

    duration = System.monotonic_time(:millisecond) - start_time

    status =
      case result do
        :ok -> :success
        {:error, _} -> :failure
      end

    :telemetry.execute(
      [:edge_agent, :bootstrap, :registration],
      %{duration: duration, count: 1, total: 1},
      %{status: status}
    )

    result
  end

  # =============================================================================
  # Step 5: Get Sent Command Executions
  # =============================================================================

  defp step_5_get_sent_command_executions(_node_id) do
    Logger.info("Step 5: Syncing commands...")

    result =
      case AdminClient.get_sent_command_executions() do
        {:ok, commands} ->
          Logger.info("Synced #{length(commands)} command(s)")

          # Store each command in local database and trigger execution
          Enum.each(commands, fn command ->
            attrs = %{
              id: command["id"],
              command_id: command["command_id"],
              node_id: Settings.get_node_id(),
              command_text: command["command_text"],
              timeout: command["timeout"],
              status: "pending"
            }

            case Commands.create_command_execution_and_enqueue_worker(attrs) do
              {:ok, _execution} ->
                Logger.debug("Stored command execution: #{command["id"]}")

              {:error, %Ecto.Changeset{errors: [id: {"has already been taken", _}]}} ->
                Logger.debug("Command execution #{command["id"]} already exists, skipping")

              {:error, changeset} ->
                Logger.warning("Failed to store command execution #{command["id"]}: #{inspect(changeset.errors)}")
            end
          end)

          :telemetry.execute(
            [:edge_agent, :commands, :sync],
            %{count: length(commands), total: length(commands)},
            %{status: :success}
          )

          :ok

        {:error, reason} ->
          Logger.warning("Command sync failed (non-fatal): #{inspect(reason)}")

          :telemetry.execute(
            [:edge_agent, :commands, :sync],
            %{count: 0, total: 0},
            %{status: :failure}
          )

          :ok
      end

    result
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp build_registration_payload(node_id, id_type, network_name) do
    %{
      node_id: node_id,
      id_type: id_type,
      network_name: network_name,
      http_port: Application.get_env(:edge_agent, :http_port, 44_000),
      ssh_port: Application.get_env(:edge_agent, :ssh_port, 40_022),
      host_metrics_port: Application.get_env(:edge_agent, :host_metrics_port, 49_100),
      wireguard_metrics_port: Application.get_env(:edge_agent, :wireguard_metrics_port, 49_586),
      http_proxy_port: Application.get_env(:edge_agent, :http_proxy_port, 43_128),
      socks5_proxy_port: Application.get_env(:edge_agent, :socks5_proxy_port, 41_080),
      version: :edge_agent |> Application.spec(:vsn) |> to_string(),
      self_update_enabled: Application.get_env(:edge_agent, :self_update_enabled, false)
    }
  end
end
