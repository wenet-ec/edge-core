# edge_agent/lib/edge_agent/metrics_server/server.ex
defmodule EdgeAgent.MetricsServer.Server do
  @moduledoc """
  GenServer that manages the node_exporter metrics collection process.

  This server handles starting, stopping, and monitoring the node_exporter
  process that collects system metrics from the host system.

  The actual business logic is delegated to EdgeAgent.MetricsServer.Impl
  to keep this module focused on GenServer concerns and make testing easier.
  """

  use GenServer
  require Logger

  alias EdgeAgent.MetricsServer.Impl

  ## Public API

  @doc """
  Starts the metrics server GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts the node_exporter process.
  """
  def start_server do
    GenServer.call(__MODULE__, :start_server, 10_000)
  end

  @doc """
  Stops the node_exporter process.
  """
  def stop_server do
    GenServer.call(__MODULE__, :stop_server, 5_000)
  end

  @doc """
  Gets the current server status.
  """
  def server_status do
    try do
      GenServer.call(__MODULE__, :server_status, 1_000)
    catch
      :exit, {:noproc, _} -> :not_started
      :exit, {:timeout, _} -> :unknown
    end
  end

  @doc """
  Gets the server configuration.
  """
  def server_config do
    try do
      GenServer.call(__MODULE__, :server_config, 1_000)
    catch
      :exit, {:noproc, _} -> %{}
      :exit, {:timeout, _} -> %{}
    end
  end

  @doc """
  Gets the primary network interface IP address.
  """
  def get_primary_interface_ip do
    try do
      GenServer.call(__MODULE__, :get_primary_interface_ip, 5_000)
    catch
      :exit, {:noproc, _} -> {:error, :server_not_started}
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    # Trap exits to handle cleanup when the process terminates
    Process.flag(:trap_exit, true)

    state = Impl.init_state()
    Logger.info("MetricsServer initialized on #{state.listen_address}:#{state.port}")

    {:ok, state}
  end

  @impl true
  def handle_call(:start_server, _from, state) do
    case Impl.start_server(state) do
      {:ok, new_state} ->
        {:reply, {:ok, new_state.node_exporter_pid}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call(:stop_server, _from, state) do
    case Impl.stop_server(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call(:server_status, _from, state) do
    {status, new_state} = Impl.get_server_status(state)
    {:reply, status, new_state}
  end

  @impl true
  def handle_call(:server_config, _from, state) do
    config = Impl.get_server_config(state)
    {:reply, config, state}
  end

  @impl true
  def handle_call(:get_primary_interface_ip, _from, state) do
    {result, new_state} = Impl.get_primary_interface_ip(state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    new_state = Impl.handle_process_exit(state, pid, reason)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({_port, {:data, _data}}, state) do
    # Handle output from node_exporter - just log it at debug level
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, state) do
    new_state = Impl.handle_port_exit(state, port, status)
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
      Impl.stop_server(state)
    end

    :ok
  end
end
