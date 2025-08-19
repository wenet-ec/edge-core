# edge_agent/lib/edge_agent/metrics_server/impl.ex
defmodule EdgeAgent.MetricsServer.Impl do
  @moduledoc """
  Implementation module for metrics server operations.

  Contains the core business logic for managing the metrics server,
  separated from GenServer concerns for easier testing.
  """

  alias EdgeAgent.MetricsServer.Config
  alias EdgeAgent.MetricsServer.Network
  alias EdgeAgent.MetricsServer.ProcessSupervisor

  require Logger

  @type state :: %{
          port: integer(),
          listen_address: String.t(),
          node_exporter_pid: pid() | integer() | nil,
          node_exporter_port: port() | nil,
          status: atom(),
          config: map(),
          primary_interface_ip: String.t() | nil,
          node_exporter_port_ref: port() | nil
        }

  @type start_result :: {:ok, state()} | {:error, term(), state()}
  @type stop_result :: {:ok, state()} | {:error, term(), state()}

  @spec init_state() :: state()
  def init_state do
    %{
      port: Config.metrics_port(),
      listen_address: Config.listen_address(),
      node_exporter_pid: nil,
      node_exporter_port: nil,
      node_exporter_port_ref: nil,
      status: :stopped,
      config: Config.build_config(),
      primary_interface_ip: nil
    }
  end

  @spec start_server(state()) :: start_result()
  def start_server(%{status: :running} = state) do
    Logger.info("MetricsServer is already running")
    {:ok, state}
  end

  def start_server(state) do
    Logger.info("Starting node_exporter metrics server...")

    case ProcessSupervisor.start_node_exporter() do
      {:ok, pid, port_ref} ->
        primary_ip = Network.detect_primary_interface_ip()

        new_state = %{
          state
          | node_exporter_pid: pid,
            node_exporter_port: state.port,
            node_exporter_port_ref: port_ref,
            status: :running,
            primary_interface_ip: primary_ip
        }

        Logger.info("MetricsServer started successfully with PID #{pid} on port #{state.port}")
        if primary_ip, do: Logger.info("Primary interface IP: #{primary_ip}")

        {:ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to start MetricsServer: #{inspect(reason)}")
        {:error, reason, %{state | status: :error}}
    end
  end

  @spec stop_server(state()) :: stop_result()
  def stop_server(%{status: :stopped} = state) do
    Logger.info("MetricsServer is already stopped")
    {:ok, state}
  end

  def stop_server(state) do
    Logger.info("Stopping node_exporter metrics server...")

    case ProcessSupervisor.stop_node_exporter(state.node_exporter_pid, state.node_exporter_port_ref) do
      :ok ->
        new_state = %{
          state
          | node_exporter_pid: nil,
            node_exporter_port: nil,
            node_exporter_port_ref: nil,
            status: :stopped,
            primary_interface_ip: nil
        }

        Logger.info("MetricsServer stopped successfully")
        {:ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to stop MetricsServer: #{inspect(reason)}")
        {:error, reason, state}
    end
  end

  @spec get_server_status(state()) :: {atom(), state()}
  def get_server_status(state) do
    status =
      if state.status == :running and state.node_exporter_pid do
        # Check if the process is still alive
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

  @spec get_server_config(state()) :: map()
  def get_server_config(state) do
    Map.merge(state.config, %{
      status: state.status,
      pid: state.node_exporter_pid,
      primary_interface_ip: state.primary_interface_ip
    })
  end

  @spec get_primary_interface_ip(state()) :: {{:ok, String.t()} | {:error, term()}, state()}
  def get_primary_interface_ip(state) do
    case state.primary_interface_ip do
      nil ->
        # Try to detect it again
        ip = Network.detect_primary_interface_ip()
        new_state = %{state | primary_interface_ip: ip}

        if ip do
          {{:ok, ip}, new_state}
        else
          {{:error, :no_interface_found}, new_state}
        end

      ip ->
        {{:ok, ip}, state}
    end
  end

  @spec handle_process_exit(state(), pid(), term()) :: state()
  def handle_process_exit(%{node_exporter_pid: pid} = state, pid, reason) do
    Logger.warning("node_exporter process #{pid} exited with reason: #{inspect(reason)}")

    %{
      state
      | node_exporter_pid: nil,
        node_exporter_port: nil,
        node_exporter_port_ref: nil,
        status: :stopped,
        primary_interface_ip: nil
    }
  end

  def handle_process_exit(state, _pid, _reason) do
    # Ignore exits from other processes
    state
  end

  @spec handle_port_exit(state(), port(), integer()) :: state()
  def handle_port_exit(%{node_exporter_port_ref: port} = state, port, status) do
    Logger.warning("node_exporter port exited with status: #{status}")

    %{
      state
      | node_exporter_pid: nil,
        node_exporter_port: nil,
        node_exporter_port_ref: nil,
        status: :stopped,
        primary_interface_ip: nil
    }
  end

  def handle_port_exit(state, _port, _status) do
    # Ignore other port messages
    state
  end
end
