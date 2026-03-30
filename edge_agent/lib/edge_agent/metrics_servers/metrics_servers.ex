# edge_agent/lib/edge_agent/metrics_servers.ex
defmodule EdgeAgent.MetricsServers do
  @moduledoc """
  Metrics servers GenServer

  Manages the node_exporter and wireguard_exporter processes for collecting
  system and WireGuard metrics from the host.
  """

  @behaviour EdgeAgent.MetricsServers.Behaviour

  use GenServer

  alias EdgeAgent.MetricsServers.Config
  alias EdgeAgent.MetricsServers.Network
  alias EdgeAgent.MetricsServers.ProcessSupervisor

  require Logger

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

    case do_start_servers(state) do
      {:ok, new_state} ->
        Logger.info("Host metrics servers started successfully on port #{new_state.host_metrics_port}")
        {:ok, new_state}

      {:error, reason, new_state} ->
        Logger.error("Failed to auto-start host metrics servers: #{inspect(reason)}")
        {:ok, new_state}
    end
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
    new_state = reset_state(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) when pid == state.wireguard_exporter_pid do
    Logger.warning("wireguard_exporter process #{pid} exited with reason: #{inspect(reason)}")
    new_state = reset_state(state)
    {:noreply, new_state}
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
    new_state = reset_state(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, state) when port == state.wireguard_exporter_port_ref do
    Logger.warning("wireguard_exporter port exited with status: #{status}")
    new_state = reset_state(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({_port, _msg}, state) do
    # Ignore other port messages
    {:noreply, state}
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

    with {:ok, node_pid, node_port} <- start_node_exporter_safe(state),
         {:ok, wg_pid, wg_port} <- start_wireguard_exporter_safe(state) do
      primary_ip = Network.detect_primary_interface_ip()

      new_state = %{
        state
        | node_exporter_pid: node_pid,
          node_exporter_port_ref: node_port,
          wireguard_exporter_pid: wg_pid,
          wireguard_exporter_port_ref: wg_port,
          status: :running,
          primary_interface_ip: primary_ip
      }

      Logger.info("Node exporter started with PID #{node_pid} on port #{state.host_metrics_port}")
      Logger.info("WireGuard exporter started with PID #{wg_pid} on port #{state.wireguard_metrics_port}")
      if primary_ip, do: Logger.info("Primary interface IP: #{primary_ip}")

      {:ok, new_state}
    else
      {:error, reason} ->
        Logger.error("Failed to start metrics exporters: #{inspect(reason)}")
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

  defp check_status(state) do
    status =
      if state.status == :running and state.node_exporter_pid do
        case state.node_exporter_pid do
          pid when is_pid(pid) ->
            if Process.alive?(pid), do: :running, else: :stopped

          pid when is_integer(pid) ->
            if ProcessSupervisor.process_exists?(pid), do: :running, else: :stopped

          _ ->
            :stopped
        end
      else
        state.status
      end

    updated_state = %{state | status: status}
    {status, updated_state}
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
