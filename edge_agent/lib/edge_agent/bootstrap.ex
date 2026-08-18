# edge_agent/lib/edge_agent/bootstrap.ex
defmodule EdgeAgent.Bootstrap do
  @moduledoc """
  Bootstrap orchestrator for edge agent startup.

  This GenServer runs exactly once during application startup and performs critical
  initialization tasks to load or create the agent installation ID, join the VPN network, discover
  and register with admin servers, and sync unprocessed command executions.

  ## Bootstrap Sequence

  1. Load or generate the node installation ID
  2. Verify enrollment key with admin
  3. Join VPN network
  4. Discover admin URLs and register with admin, using HTTP fallback if needed
  5. Sync unprocessed command executions
  6. Register node aliases from `ALIASES` best-effort

  ## Failure Handling

  Bootstrap failures stop the GenServer's `init/1` with the failure reason.
  Under the application supervisor's `:one_for_one` strategy that triggers
  a restart; once Bootstrap exhausts its restart intensity the entire
  application supervisor terminates and the agent exits — i.e. fatal in
  practice, but with a few retries first. Failure modes:

  - Node-ID persistence failure → Can't identify node
  - Enrollment / VPN join failure → Can't communicate with admins
  - Registration failure → Can't authenticate with admin

  Non-fatal conditions (logged as warning, bootstrap continues):
  - Admin discovery returns empty → Triggers HTTP fallback mode
  - Command sync failures → Will retry later via `EdgeAgent.LocalScheduler.Tasks.sync_unprocessed_executions/0`

  ## Configuration

  All values read from Application config (set in runtime.exs):
  - `:enrollment_key` - Admin enrollment key blob (base64)
  - `:recovery_key` - Optional node recovery key used only when local identity is absent
  - `:public_enrollment_key_urls` - List of URLs to fetch enrollment key blob (tried in order)
  - `:run_bootstrap` - Whether to run bootstrap (default: true)
  - `:api_port` - Agent HTTP API port (sent to admin as `http_port`)
  - `:ssh_port` - Agent SSH server port
  - `:host_metrics_port` - Node exporter port
  - `:wireguard_metrics_port` - WireGuard exporter port
  - `:http_proxy_port` - HTTP proxy port
  - `:socks5_proxy_port` - SOCKS5 proxy port
  - `:vpn_ready_timeout_seconds` - VPN verification timeout in seconds (default: 30)
  - `:aliases` - List of friendly name aliases to register with admin (default: [])

  """

  use GenServer

  alias EdgeAgent.AdminGateway.Client
  alias EdgeAgent.AdminGateway.Discovery
  alias EdgeAgent.Commands
  alias EdgeAgent.Enrollment
  alias EdgeAgent.Identity
  alias EdgeAgent.Registration
  alias EdgeAgent.Vpn

  require Logger

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

  defp do_bootstrap do
    with {:ok, identity} <- step_1_determine_identity(),
         :ok <- step_2_verify_enrollment(identity.recovery_key),
         :ok <- step_3_join_vpn(identity.node_id),
         :ok <- step_4_discover_and_register(identity),
         :ok <- step_5_sync_unprocessed_command_executions(identity.node_id),
         :ok <- step_6_register_aliases() do
      Logger.info("All bootstrap steps completed")
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Bootstrap step failed: #{inspect(reason)}")
        error
    end
  end

  defp step_1_determine_identity do
    Logger.info("Step 1: Determining node identity...")
    Identity.determine()
  end

  defp step_2_verify_enrollment(recovery_key) do
    Logger.info("Step 2: Verifying enrollment key...")
    Enrollment.ensure_verified(recovery_key)
  end

  defp step_3_join_vpn(node_id) do
    Logger.info("Step 3: Joining VPN network...")
    Vpn.join_if_needed(node_id)
  end

  defp step_4_discover_and_register(%{node_id: node_id, recovery_key: recovery_key}) do
    Logger.info("Step 4: Discovering admins and registering...")
    start_time = System.monotonic_time(:millisecond)

    network_name = discover_and_log_admins()
    result = Registration.register(%{node_id: node_id, recovery_key: recovery_key}, network_name)

    emit_registration_telemetry(result, start_time)
    result
  end

  defp discover_and_log_admins do
    {:ok, network_name, admin_urls} = Discovery.discover_admins()

    if network_name do
      Logger.info("Network: #{network_name}")
    end

    case admin_urls do
      [] -> Logger.warning("No admins discovered in VPN - will use HTTP fallback if configured")
      urls -> Logger.info("Discovered #{length(urls)} admin(s)")
    end

    network_name
  end

  defp emit_registration_telemetry(result, start_time) do
    duration = System.monotonic_time(:millisecond) - start_time
    status = if result == :ok, do: :success, else: :failure

    :telemetry.execute(
      [:edge_agent, :bootstrap, :registration],
      %{duration: duration, count: 1, total: 1},
      %{status: status}
    )
  end

  defp step_5_sync_unprocessed_command_executions(_node_id) do
    Logger.info("Step 5: Syncing unprocessed command executions...")

    Commands.sync_unprocessed_command_executions()

    :ok
  end

  defp step_6_register_aliases do
    aliases = Application.get_env(:edge_agent, :aliases, [])

    if aliases != [] do
      Logger.info("Step 6: Registering #{length(aliases)} alias(es)...")

      Enum.each(aliases, fn name ->
        case Client.register_alias(name) do
          :ok ->
            Logger.info("Alias registered: #{name}")

          {:error, {:conflict, _reason}} ->
            Logger.warning("Alias already registered: #{inspect(name)}")

          {:error, reason} ->
            Logger.warning("Failed to register alias #{inspect(name)}: #{inspect(reason)}")
        end
      end)
    end

    :ok
  end
end
