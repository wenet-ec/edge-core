# edge_agent/lib/edge_agent/bootstrap.ex
defmodule EdgeAgent.Bootstrap do
  @moduledoc """
  Runs the one-time startup sequence that establishes local identity, verifies
  enrollment, joins the VPN, registers with Admin, and synchronizes pending
  command executions. Bootstrap failures are reported to the supervisor for
  restart; optional discovery and synchronization work can continue in a
  degraded state.

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
