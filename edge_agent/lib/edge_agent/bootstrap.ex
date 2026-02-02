# edge_agent/lib/edge_agent/bootstrap.ex
defmodule EdgeAgent.Bootstrap do
  @moduledoc """
  One-time bootstrap orchestrator for edge agent startup.

  This GenServer runs exactly once during application startup and performs critical
  initialization tasks to establish agent identity, join the VPN network, discover
  and register with admin servers, and sync unprocessed command executions.

  ## Key Concepts

  - **Node Identity**: Persistent or random UUID identifying this agent
  - **VPN Join**: Connects to cluster network via Netmaker enrollment token
  - **Admin Discovery**: Finds admin servers via Netmaker API (no hardcoded addresses)
  - **Registration**: Registers node with admin and receives API token
  - **Command Sync**: Syncs unprocessed command executions (both sent and pending)

  ## Responsibilities

  1. **Identity Determination**
     - Try persistent system ID (machine-id, hardware UUID)
     - Fall back to random UUID if persistent ID unavailable
     - Store identity in Settings database for persistence

  2. **VPN Network Join**
     - Join edge cluster network using enrollment token
     - Verify netclient connection and health
     - Obtain VPN IP address for communication

  3. **Admin Discovery and Registration**
     - Query Netmaker for hosts in admin cluster network
     - Extract admin URLs from host metadata (or use HTTP fallback if none found)
     - Register with admin and receive credentials

  4. **Command Sync**
     - Sync unprocessed command executions from admin
     - Fetches both "sent" (already acknowledged) and "pending" (needs acknowledgment)
     - Acknowledges pending executions before storing locally
     - Store in local database and enqueue for execution
     - Handle duplicates gracefully

  ## Bootstrap Sequence

  ```
  1. Determine node identity (persistent → random)
  2. Join VPN network via enrollment token
  3. Discover admin URLs and register with admin (with HTTP fallback)
  4. Sync unprocessed command executions (sent + pending)
  ```

  ## Failure Handling

  Bootstrap failures are **FATAL** and crash the supervision tree:
  - Identity determination failure → Can't identify node
  - VPN join failure → Can't communicate with admins
  - Registration failure → Can't authenticate with admin

  Non-fatal conditions (logged as warning, bootstrap continues):
  - Admin discovery returns empty → Triggers HTTP fallback mode
  - Command sync failures → Will retry later via SyncUnprocessedExecutionWorker

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
  - `:fallback_admin_urls` - HTTP fallback URLs when VPN unavailable (list)

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
          Logger.error("Bootstrap failed (FATAL): #{inspect(reason)}")
          Logger.error("Agent cannot continue without successful bootstrap - shutting down")
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
         :ok <- step_3_discover_and_register(node_id, id_type),
         :ok <- step_4_sync_unprocessed_command_executions(node_id) do
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
  # Step 3: Discover Admins and Register Node
  # =============================================================================

  defp step_3_discover_and_register(node_id, id_type) do
    Logger.info("Step 3: Discovering admins and registering...")

    # Discovery always succeeds - returns empty list if no admins found
    {:ok, network_name, admin_urls} = Discovery.discover_admins()

    if network_name do
      Logger.info("Network: #{network_name}")
    end

    case admin_urls do
      [] ->
        Logger.warning("No admins discovered in VPN - will use HTTP fallback if configured")

      urls ->
        Logger.info("Discovered #{length(urls)} admin(s)")
    end

    # Register with admin (uses discovered URLs or fallback)
    Logger.info("Registering with admin...")

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
  # Step 4: Sync Unprocessed Command Executions
  # =============================================================================

  defp step_4_sync_unprocessed_command_executions(_node_id) do
    Logger.info("Step 4: Syncing unprocessed command executions...")

    # Use shared sync function (also used by SyncUnprocessedExecutionWorker)
    Commands.sync_unprocessed_command_executions()

    # Always return :ok (sync failures are non-fatal)
    :ok
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
      self_update_enabled: Application.get_env(:edge_agent, :self_update_enabled, false),
      relay_enabled: Application.get_env(:edge_agent, :relay_enabled, false)
    }
  end
end
