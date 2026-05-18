# edge_agent/lib/edge_agent/metrics_servers/metrics_servers.ex
defmodule EdgeAgent.MetricsServers do
  @moduledoc """
  Metrics servers GenServer

  Manages the node_exporter and wireguard_exporter processes for collecting
  system and WireGuard metrics from the host.

  ## Startup behaviour

  `init/1` always returns `{:ok, state}` even if launching the exporters
  fails — the supervisor stays up so the agent can keep running without
  metrics rather than crash-looping. Operators (and `EdgeAgentHealth`) can
  query `servers_status/0` to detect this state, which will return `:error`
  when the auto-start failed.

  ## Self-healing

  A `:check_health` timer fires every `@check_health_interval_ms` and runs
  `check_status/1` against OS reality (tracked PID still alive via
  `kill -0`; if not, port-rediscover via `ss` / `pgrep`). If both exporters
  are gone, the timer respawns them.

  This protects against two real failure modes seen in production:
  - Host reboot leaves the GenServer with stale PIDs that no longer
    correspond to the post-boot exporter processes (the `init/1` spawn
    succeeds but PID discovery raced and recorded the wrong PID).
  - A spurious `{:exit_status, _}` port message tears down tracked state
    while the OS process is actually still alive — reconciliation
    re-adopts via port probe instead of staying permanently `:stopped`.

  Exit-signal handlers (`handle_node_exporter_down/1` etc.) clear ONLY
  the affected exporter's tracked state — they no longer tear down the
  sibling. The reconciler handles recovery.
  """

  @behaviour EdgeAgent.MetricsServers.Behaviour

  use GenServer

  alias EdgeAgent.MetricsServers.Config
  alias EdgeAgent.MetricsServers.Network
  alias EdgeAgent.MetricsServers.ProcessSupervisor

  require Logger

  # Periodic liveness reconciliation. Runs in addition to the on-demand
  # `servers_status/0` path so the GenServer self-heals (port-rediscovers
  # an orphaned exporter we lost track of, or respawns if both are gone)
  # even when nothing is asking.
  @check_health_interval_ms 30_000

  # Client API
  @impl EdgeAgent.MetricsServers.Behaviour
  def start_servers, do: GenServer.call(__MODULE__, :start_servers, 10_000)

  @impl EdgeAgent.MetricsServers.Behaviour
  def stop_servers, do: GenServer.call(__MODULE__, :stop_servers, 5_000)

  @impl EdgeAgent.MetricsServers.Behaviour
  def servers_status do
    GenServer.call(__MODULE__, :servers_status, 1_000)
  catch
    :exit, {:noproc, _} -> :not_started
    :exit, {:timeout, _} -> :unknown
  end

  @impl EdgeAgent.MetricsServers.Behaviour
  def servers_config do
    GenServer.call(__MODULE__, :servers_config, 1_000)
  catch
    :exit, {:noproc, _} -> %{}
    :exit, {:timeout, _} -> %{}
  end

  @impl EdgeAgent.MetricsServers.Behaviour
  def get_primary_interface_ip do
    GenServer.call(__MODULE__, :get_primary_interface_ip, 5_000)
  catch
    :exit, {:noproc, _} -> {:error, :servers_not_started}
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # GenServer callbacks
  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)

    state = %{
      host_metrics_port: Config.host_metrics_port(),
      wireguard_metrics_port: Config.wireguard_metrics_port(),
      listen_address: Config.listen_address(),
      node_exporter_pid: nil,
      node_exporter_port_ref: nil,
      wireguard_exporter_pid: nil,
      wireguard_exporter_port_ref: nil,
      status: :stopped,
      config: Config.build_config(),
      primary_interface_ip: nil
    }

    result =
      case do_start_servers(state) do
        {:ok, new_state} ->
          Logger.info("Host metrics servers started successfully on port #{new_state.host_metrics_port}")
          {:ok, new_state}

        {:error, reason, new_state} ->
          Logger.error("Failed to auto-start host metrics servers: #{inspect(reason)}")
          {:ok, new_state}
      end

    # Best-effort flush of the init-time Logger backlog. Under releases, the
    # `:logger` handler attaches synchronously but its console handler can
    # still buffer the first few writes before the IO group leader stabilises,
    # so these Logger.info/error lines occasionally never reach docker logs
    # at all. Flushing here makes them appear in stdout. Safe no-op if the
    # backend is already drained.
    _ = Logger.flush()

    schedule_check_health()
    result
  end

  @impl true
  def handle_call(:start_servers, _from, state) do
    case state.status do
      :running ->
        Logger.info("Metrics servers already running")
        {:reply, {:ok, state.node_exporter_pid}, state}

      _status ->
        case do_start_servers(state) do
          {:ok, new_state} ->
            {:reply, {:ok, new_state.node_exporter_pid}, new_state}

          {:error, reason, new_state} ->
            {:reply, {:error, reason}, new_state}
        end
    end
  end

  @impl true
  def handle_call(:stop_servers, _from, state) do
    case state.status do
      :stopped ->
        Logger.info("Metrics servers already stopped")
        {:reply, :ok, state}

      :running ->
        case do_stop_servers(state) do
          {:ok, new_state} ->
            {:reply, :ok, new_state}

          {:error, reason, new_state} ->
            {:reply, {:error, reason}, new_state}
        end

      _status ->
        Logger.warning("Metrics servers in unknown state, marking as stopped")
        new_state = reset_state(state)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:servers_status, _from, state) do
    {status, new_state} = check_status(state)
    {:reply, status, new_state}
  end

  @impl true
  def handle_call(:servers_config, _from, state) do
    config =
      Map.merge(state.config, %{
        status: state.status,
        pid: state.node_exporter_pid,
        primary_interface_ip: state.primary_interface_ip
      })

    {:reply, config, state}
  end

  @impl true
  def handle_call(:get_primary_interface_ip, _from, state) do
    case state.primary_interface_ip do
      nil ->
        ip = Network.detect_primary_interface_ip()
        new_state = %{state | primary_interface_ip: ip}

        result = if ip, do: {:ok, ip}, else: {:error, :no_interface_found}
        {:reply, result, new_state}

      ip ->
        {:reply, {:ok, ip}, state}
    end
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) when pid == state.node_exporter_pid do
    Logger.warning("node_exporter process #{pid} exited with reason: #{inspect(reason)}")
    {:noreply, handle_node_exporter_down(state)}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) when pid == state.wireguard_exporter_pid do
    Logger.warning("wireguard_exporter process #{pid} exited with reason: #{inspect(reason)}")
    {:noreply, handle_wireguard_exporter_down(state)}
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    # Ignore exits from other processes
    {:noreply, state}
  end

  @impl true
  def handle_info({_port, {:data, _data}}, state) do
    # Handle output from node_exporter - just log it at debug level
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, state) when port == state.node_exporter_port_ref do
    Logger.warning("node_exporter port exited with status: #{status}")
    {:noreply, handle_node_exporter_down(state)}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, state) when port == state.wireguard_exporter_port_ref do
    Logger.warning("wireguard_exporter port exited with status: #{status}")
    {:noreply, handle_wireguard_exporter_down(state)}
  end

  @impl true
  def handle_info({_port, _msg}, state) do
    # Ignore other port messages
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_health, state) do
    {_status, new_state} = check_status(state)

    recovered_state =
      if new_state.status == :stopped and
           is_nil(new_state.node_exporter_pid) and
           is_nil(new_state.wireguard_exporter_pid) do
        Logger.warning("Metrics exporters not running — attempting auto-recovery")

        case do_start_servers(new_state) do
          {:ok, started_state} ->
            Logger.info("Auto-recovery succeeded; metrics exporters back online")
            started_state

          {:error, reason, errored_state} ->
            Logger.error("Auto-recovery failed: #{inspect(reason)} — will retry next interval")
            errored_state
        end
      else
        new_state
      end

    schedule_check_health()
    {:noreply, recovered_state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.node_exporter_pid != nil or state.wireguard_exporter_pid != nil do
      Logger.info("Cleaning up metrics exporter processes on shutdown...")
      do_stop_servers(state)
    end

    :ok
  end

  # Private functions
  defp do_start_servers(state) do
    Logger.info("Starting metrics exporters...")

    case start_node_exporter_safe(state) do
      {:ok, node_pid, node_port} ->
        # Record the node_exporter in state *before* starting wireguard, so a
        # wireguard-start failure can clean it up instead of orphaning it.
        state_with_node = %{
          state
          | node_exporter_pid: node_pid,
            node_exporter_port_ref: node_port
        }

        Logger.info("Node exporter started with PID #{node_pid} on port #{state.host_metrics_port}")

        case start_wireguard_exporter_safe(state_with_node) do
          {:ok, wg_pid, wg_port} ->
            primary_ip = Network.detect_primary_interface_ip()

            Logger.info("WireGuard exporter started with PID #{wg_pid} on port #{state.wireguard_metrics_port}")
            if primary_ip, do: Logger.info("Primary interface IP: #{primary_ip}")

            new_state = %{
              state_with_node
              | wireguard_exporter_pid: wg_pid,
                wireguard_exporter_port_ref: wg_port,
                status: :running,
                primary_interface_ip: primary_ip
            }

            {:ok, new_state}

          {:error, reason} ->
            Logger.error("WireGuard exporter failed to start; stopping node_exporter: #{inspect(reason)}")
            ProcessSupervisor.stop_node_exporter(node_pid, node_port)
            {:error, reason, %{state | status: :error}}
        end

      {:error, reason} ->
        Logger.error("Failed to start node_exporter: #{inspect(reason)}")
        {:error, reason, %{state | status: :error}}
    end
  end

  defp start_node_exporter_safe(_state) do
    case ProcessSupervisor.start_node_exporter() do
      {:ok, pid, port_ref} ->
        {:ok, pid, port_ref}

      {:error, reason} ->
        Logger.error("Failed to start node_exporter: #{inspect(reason)}")
        {:error, {:node_exporter_failed, reason}}
    end
  end

  defp start_wireguard_exporter_safe(_state) do
    case ProcessSupervisor.start_wireguard_exporter() do
      {:ok, pid, port_ref} ->
        {:ok, pid, port_ref}

      {:error, reason} ->
        Logger.error("Failed to start wireguard_exporter: #{inspect(reason)}")
        {:error, {:wireguard_exporter_failed, reason}}
    end
  end

  defp do_stop_servers(state) do
    Logger.info("Stopping metrics exporters...")

    # Stop both exporters
    node_result = ProcessSupervisor.stop_node_exporter(state.node_exporter_pid, state.node_exporter_port_ref)

    wg_result =
      ProcessSupervisor.stop_wireguard_exporter(state.wireguard_exporter_pid, state.wireguard_exporter_port_ref)

    case {node_result, wg_result} do
      {:ok, :ok} ->
        new_state = reset_state(state)
        Logger.info("Metrics exporters stopped successfully")
        {:ok, new_state}

      {node_err, wg_err} ->
        Logger.error(
          "Failed to stop exporters - node_exporter: #{inspect(node_err)}, wireguard_exporter: #{inspect(wg_err)}"
        )

        {:error, {:stop_failed, %{node_exporter: node_err, wireguard_exporter: wg_err}}, state}
    end
  end

  # Reconciles state with OS reality. Replaces the previous sticky logic that
  # short-circuited on `state.status != :running`, which left the GenServer
  # permanently reporting `:stopped` after a single transient `kill -0`
  # failure (e.g. fork EAGAIN under boot-time fork pressure, or a pgrep race
  # that picked a short-lived PID).
  #
  # For each exporter we:
  #   1. Trust the tracked PID if it's still alive.
  #   2. If tracked PID is missing or dead, port-rediscover via
  #      `ProcessSupervisor.discover_pid_by_port/3`. If we find a live
  #      exporter we didn't spawn, adopt it (port_ref stays `nil` — orphan
  #      adoptions can't receive `{:exit_status, _}` notifications, but the
  #      periodic `:check_health` re-probes anyway, so no liveness gap).
  #   3. If neither path yields a live process, declare it down.
  defp check_status(state) do
    {node_alive?, node_pid, node_port_ref} =
      reconcile_exporter(
        state.node_exporter_pid,
        state.node_exporter_port_ref,
        state.host_metrics_port,
        "node_exporter",
        ProcessSupervisor.node_exporter_pgrep_pattern(state.host_metrics_port)
      )

    {wg_alive?, wg_pid, wg_port_ref} =
      reconcile_exporter(
        state.wireguard_exporter_pid,
        state.wireguard_exporter_port_ref,
        state.wireguard_metrics_port,
        "prometheus_wireguard_exporter",
        ProcessSupervisor.wireguard_exporter_pgrep_pattern(state.wireguard_metrics_port)
      )

    status = if node_alive? and wg_alive?, do: :running, else: :stopped

    updated_state = %{
      state
      | node_exporter_pid: node_pid,
        node_exporter_port_ref: node_port_ref,
        wireguard_exporter_pid: wg_pid,
        wireguard_exporter_port_ref: wg_port_ref,
        status: status
    }

    {status, updated_state}
  end

  # Returns `{alive?, pid_or_nil, port_ref_or_nil}` for a single exporter.
  # `port_ref` is preserved if we adopted via port discovery (i.e. the
  # tracked pid was dead but the configured port has a live exporter):
  # since we didn't spawn the adopted process, we have no port to track.
  defp reconcile_exporter(tracked_pid, port_ref, port, binary_name, pgrep_pattern) do
    if exporter_alive?(tracked_pid) do
      {true, tracked_pid, port_ref}
    else
      case ProcessSupervisor.discover_pid_by_port(port, binary_name, pgrep_pattern) do
        {:ok, discovered_pid} ->
          if tracked_pid != nil and discovered_pid != tracked_pid do
            Logger.warning(
              "Adopted orphan #{binary_name} PID #{discovered_pid} on port #{port} (tracked PID #{tracked_pid} was dead)"
            )
          end

          {true, discovered_pid, nil}

        {:error, _} ->
          {false, nil, nil}
      end
    end
  end

  defp exporter_alive?(nil), do: false
  defp exporter_alive?(pid) when is_integer(pid), do: ProcessSupervisor.process_exists?(pid)

  defp schedule_check_health do
    Process.send_after(self(), :check_health, @check_health_interval_ms)
  end

  # On exit-signal from one exporter, clear ONLY that exporter's tracked
  # state. The previous implementation tore down the healthy sibling too,
  # which (a) caused a metrics blackout on every spurious port message and
  # (b) didn't actually guarantee cleanup since `Port.close` doesn't always
  # SIGTERM detached OS children. The periodic `:check_health` reconciler
  # now handles full recovery — either it re-adopts the surviving sibling
  # via port probe, or, if both are gone, respawns both atomically.
  defp handle_node_exporter_down(state) do
    %{
      state
      | node_exporter_pid: nil,
        node_exporter_port_ref: nil,
        status: :stopped
    }
  end

  defp handle_wireguard_exporter_down(state) do
    %{
      state
      | wireguard_exporter_pid: nil,
        wireguard_exporter_port_ref: nil,
        status: :stopped
    }
  end

  defp reset_state(state) do
    %{
      state
      | node_exporter_pid: nil,
        node_exporter_port_ref: nil,
        wireguard_exporter_pid: nil,
        wireguard_exporter_port_ref: nil,
        status: :stopped,
        primary_interface_ip: nil
    }
  end
end
