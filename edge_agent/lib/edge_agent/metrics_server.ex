# edge_agent/lib/edge_agent/metrics_server.ex
defmodule EdgeAgent.MetricsServer do
  @moduledoc """
  Metrics server GenServer

  Manages the node_exporter process for collecting system metrics from the host.
  """

  @behaviour EdgeAgent.MetricsServer.Behaviour

  use GenServer

  alias EdgeAgent.MetricsServer.Config
  alias EdgeAgent.MetricsServer.Network
  alias EdgeAgent.MetricsServer.ProcessSupervisor

  require Logger

  # Client API
  @impl EdgeAgent.MetricsServer.Behaviour
  def start_server, do: GenServer.call(__MODULE__, :start_server, 10_000)

  @impl EdgeAgent.MetricsServer.Behaviour
  def stop_server, do: GenServer.call(__MODULE__, :stop_server, 5_000)

  @impl EdgeAgent.MetricsServer.Behaviour
  def server_status do
    GenServer.call(__MODULE__, :server_status, 1_000)
  catch
    :exit, {:noproc, _} -> :not_started
    :exit, {:timeout, _} -> :unknown
  end

  @impl EdgeAgent.MetricsServer.Behaviour
  def server_config do
    GenServer.call(__MODULE__, :server_config, 1_000)
  catch
    :exit, {:noproc, _} -> %{}
    :exit, {:timeout, _} -> %{}
  end

  @impl EdgeAgent.MetricsServer.Behaviour
  def get_primary_interface_ip do
    GenServer.call(__MODULE__, :get_primary_interface_ip, 5_000)
  catch
    :exit, {:noproc, _} -> {:error, :server_not_started}
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
      listen_address: Config.listen_address(),
      node_exporter_pid: nil,
      node_exporter_port_ref: nil,
      status: :stopped,
      config: Config.build_config(),
      primary_interface_ip: nil
    }

    case do_start_server(state) do
      {:ok, new_state} ->
        Logger.info("Host metrics server started successfully on port #{new_state.host_metrics_port}")
        {:ok, new_state}

      {:error, reason, new_state} ->
        Logger.error("Failed to auto-start host metrics server: #{inspect(reason)}")
        {:ok, new_state}
    end
  end

  @impl true
  def handle_call(:start_server, _from, state) do
    case state.status do
      :running ->
        Logger.info("Metrics server already running")
        {:reply, {:ok, state.node_exporter_pid}, state}

      _status ->
        case do_start_server(state) do
          {:ok, new_state} ->
            {:reply, {:ok, new_state.node_exporter_pid}, new_state}

          {:error, reason, new_state} ->
            {:reply, {:error, reason}, new_state}
        end
    end
  end

  @impl true
  def handle_call(:stop_server, _from, state) do
    case state.status do
      :stopped ->
        Logger.info("Metrics server already stopped")
        {:reply, :ok, state}

      :running ->
        case do_stop_server(state) do
          {:ok, new_state} ->
            {:reply, :ok, new_state}

          {:error, reason, new_state} ->
            {:reply, {:error, reason}, new_state}
        end

      _status ->
        Logger.warning("Metrics server in unknown state, marking as stopped")
        new_state = reset_state(state)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:server_status, _from, state) do
    {status, new_state} = check_status(state)
    {:reply, status, new_state}
  end

  @impl true
  def handle_call(:server_config, _from, state) do
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
  def handle_info({_port, _msg}, state) do
    # Ignore other port messages
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.node_exporter_pid do
      Logger.info("Cleaning up node_exporter process on shutdown...")
      do_stop_server(state)
    end

    :ok
  end

  # Private functions
  defp do_start_server(state) do
    Logger.info("Starting node_exporter metrics server...")

    case ProcessSupervisor.start_node_exporter() do
      {:ok, pid, port_ref} ->
        primary_ip = Network.detect_primary_interface_ip()

        new_state = %{
          state
          | node_exporter_pid: pid,
            node_exporter_port_ref: port_ref,
            status: :running,
            primary_interface_ip: primary_ip
        }

        Logger.info("Host metrics server started successfully with PID #{pid} on port #{state.host_metrics_port}")
        if primary_ip, do: Logger.info("Primary interface IP: #{primary_ip}")

        {:ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to start metrics server: #{inspect(reason)}")
        {:error, reason, %{state | status: :error}}
    end
  end

  defp do_stop_server(state) do
    Logger.info("Stopping node_exporter metrics server...")

    case ProcessSupervisor.stop_node_exporter(state.node_exporter_pid, state.node_exporter_port_ref) do
      :ok ->
        new_state = reset_state(state)
        Logger.info("Metrics server stopped successfully")
        {:ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to stop metrics server: #{inspect(reason)}")
        {:error, reason, state}
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
        status: :stopped,
        primary_interface_ip: nil
    }
  end
end
