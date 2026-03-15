# edge_agent/lib/edge_agent/bootstrap.ex
defmodule EdgeAgent.Bootstrap do
  @moduledoc """
  One-time bootstrap orchestrator for edge agent startup.

  This GenServer runs exactly once during application startup and performs critical
  initialization tasks to establish agent identity, join the VPN network, discover
  and register with admin servers, and sync unprocessed command executions.

  ## Bootstrap Sequence

  ```
  1. Determine node identity (persistent → random)
  2. Verify enrollment key with admin
  3. Join VPN network
  4. Discover admin URLs and register with admin (with HTTP fallback)
  5. Sync unprocessed command executions (sent + pending)
  ```

  ## Failure Handling

  Bootstrap failures are **FATAL** and crash the supervision tree:
  - Identity determination failure → Can't identify node
  - Enrollment / VPN join failure → Can't communicate with admins
  - Registration failure → Can't authenticate with admin

  Non-fatal conditions (logged as warning, bootstrap continues):
  - Admin discovery returns empty → Triggers HTTP fallback mode
  - Command sync failures → Will retry later via SyncUnprocessedExecutionWorker

  ## Configuration

  All values read from Application config (set in runtime.exs):
  - `:enrollment_key` - Admin enrollment key blob (base64)
  - `:public_enrollment_key_url` - URL to fetch enrollment key blob if env not set
  - `:run_bootstrap` - Whether to run bootstrap (default: true)
  - `:http_port` - Agent HTTP API port (default: 44000)
  - `:ssh_port` - Agent SSH server port (default: 40022)
  - `:host_metrics_port` - Node exporter port (default: 49100)
  - `:wireguard_metrics_port` - WireGuard exporter port (default: 49586)
  - `:http_proxy_port` - HTTP proxy port (default: 43128)
  - `:socks5_proxy_port` - SOCKS5 proxy port (default: 41080)
  - `:vpn_ready_timeout_seconds` - VPN verification timeout in seconds (default: 30)

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
  alias EdgeAgent.Enrollment
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
         :ok <- step_2_verify_enrollment(),
         :ok <- step_3_join_vpn(node_id),
         :ok <- step_4_discover_and_register(node_id, id_type),
         :ok <- step_5_sync_unprocessed_command_executions(node_id) do
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

    {:ok, node_id, id_type} = Identity.determine()
    Logger.info("Node identity: #{String.slice(node_id, 0, 8)}... (#{id_type})")

    Settings.set_node_id(node_id)
    Settings.set_id_type(id_type)

    {:ok, node_id, id_type}
  end

  # =============================================================================
  # Step 2: Verify Enrollment Key
  # =============================================================================

  defp step_2_verify_enrollment do
    Logger.info("Step 2: Verifying enrollment key...")
    Enrollment.ensure_verified()
  end

  # =============================================================================
  # Step 3: Join VPN
  # =============================================================================

  defp step_3_join_vpn(node_id) do
    Logger.info("Step 3: Joining VPN network...")
    Vpn.join_if_needed(node_id)
  end

  # =============================================================================
  # Step 4: Discover Admins and Register Node
  # =============================================================================

  defp step_4_discover_and_register(node_id, id_type) do
    Logger.info("Step 4: Discovering admins and registering...")

    {:ok, network_name, admin_urls} = Discovery.discover_admins()

    if network_name do
      Logger.info("Network: #{network_name}")
    end

    case admin_urls do
      [] -> Logger.warning("No admins discovered in VPN - will use HTTP fallback if configured")
      urls -> Logger.info("Discovered #{length(urls)} admin(s)")
    end

    Logger.info("Registering with admin...")

    start_time = System.monotonic_time(:millisecond)
    payload = build_registration_payload(node_id, id_type, network_name)

    result =
      case AdminClient.register_node(payload) do
        {:ok, node_data} ->
          api_token = node_data["api_token"]
          proxy_password = node_data["proxy_password"]
          lan_domain = node_data["lan_domain"]

          cond do
            is_nil(api_token) ->
              {:error, "Registration response missing api_token"}

            is_nil(proxy_password) ->
              {:error, "Registration response missing proxy_password"}

            true ->
              Settings.set_api_token(api_token)
              Settings.set_proxy_password(proxy_password)
              if lan_domain, do: Settings.set_lan_domain(lan_domain)
              Logger.info("Successfully registered with admin")
              :ok
          end

        {:error, reason} ->
          {:error, "Registration failed: #{inspect(reason)}"}
      end

    duration = System.monotonic_time(:millisecond) - start_time

    status = if result == :ok, do: :success, else: :failure

    :telemetry.execute(
      [:edge_agent, :bootstrap, :registration],
      %{duration: duration, count: 1, total: 1},
      %{status: status}
    )

    result
  end

  # =============================================================================
  # Step 5: Sync Unprocessed Command Executions
  # =============================================================================

  defp step_5_sync_unprocessed_command_executions(_node_id) do
    Logger.info("Step 5: Syncing unprocessed command executions...")

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
      self_update_enabled: Application.get_env(:edge_agent, :self_update_enabled, false)
    }
  end
end
