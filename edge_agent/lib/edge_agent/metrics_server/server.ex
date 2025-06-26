# edge_agent/lib/edge_agent/metrics_server/server.ex
defmodule EdgeAgent.MetricsServer.Server do
  @moduledoc """
  GenServer that manages the node_exporter metrics collection process.

  This server handles starting, stopping, and monitoring the node_exporter
  process that collects system metrics from the host system.
  """

  use GenServer
  require Logger

  # Hardcoded configuration - no config files needed
  @metrics_port 9100
  @listen_address "0.0.0.0"
  @node_exporter_binary "/usr/local/bin/node_exporter"
  @host_proc_path "/host/proc"
  @host_sys_path "/host/sys"
  @host_root_path "/host"

  defstruct [
    :port,
    :listen_address,
    :node_exporter_pid,
    :node_exporter_port,
    :status,
    :config,
    :primary_interface_ip,
    :node_exporter_port_ref
  ]

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

    state = %__MODULE__{
      port: @metrics_port,
      listen_address: @listen_address,
      status: :stopped,
      config: build_config()
    }

    Logger.info("MetricsServer initialized on #{@listen_address}:#{@metrics_port}")

    {:ok, state}
  end

  @impl true
  def handle_call(:start_server, _from, %{status: :running} = state) do
    Logger.info("MetricsServer is already running")
    {:reply, {:ok, state.node_exporter_pid}, state}
  end

  @impl true
  def handle_call(:start_server, _from, state) do
    Logger.info("Starting node_exporter metrics server...")

    case start_node_exporter(state) do
      {:ok, pid, port, port_ref} ->
        primary_ip = detect_primary_interface_ip()

        new_state = %{state |
          node_exporter_pid: pid,
          node_exporter_port: port,
          node_exporter_port_ref: port_ref,
          status: :running,
          primary_interface_ip: primary_ip
        }

        Logger.info("MetricsServer started successfully with PID #{pid} on port #{port}")
        if primary_ip, do: Logger.info("Primary interface IP: #{primary_ip}")

        {:reply, {:ok, pid}, new_state}

      {:error, reason} ->
        Logger.error("Failed to start MetricsServer: #{inspect(reason)}")
        {:reply, {:error, reason}, %{state | status: :error}}
    end
  end

  @impl true
  def handle_call(:stop_server, _from, %{status: :stopped} = state) do
    Logger.info("MetricsServer is already stopped")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:stop_server, _from, state) do
    Logger.info("Stopping node_exporter metrics server...")

    case stop_node_exporter(state.node_exporter_pid, state.node_exporter_port_ref) do
      :ok ->
        new_state = %{state |
          node_exporter_pid: nil,
          node_exporter_port: nil,
          node_exporter_port_ref: nil,
          status: :stopped,
          primary_interface_ip: nil
        }

        Logger.info("MetricsServer stopped successfully")
        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to stop MetricsServer: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:server_status, _from, state) do
    status = if state.status == :running and state.node_exporter_pid do
      # Check if the process is still alive
      case state.node_exporter_pid do
        pid when is_pid(pid) ->
          if Process.alive?(pid), do: :running, else: :stopped
        pid when is_integer(pid) ->
          if process_exists?(pid), do: :running, else: :stopped
        _ ->
          :stopped
      end
    else
      state.status
    end

    {:reply, status, %{state | status: status}}
  end

  @impl true
  def handle_call(:server_config, _from, state) do
    config = Map.merge(state.config, %{
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
        # Try to detect it again
        ip = detect_primary_interface_ip()
        new_state = %{state | primary_interface_ip: ip}

        if ip do
          {:reply, {:ok, ip}, new_state}
        else
          {:reply, {:error, :no_interface_found}, new_state}
        end

      ip ->
        {:reply, {:ok, ip}, state}
    end
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{node_exporter_pid: pid} = state) do
    Logger.warning("node_exporter process #{pid} exited with reason: #{inspect(reason)}")

    new_state = %{state |
      node_exporter_pid: nil,
      node_exporter_port: nil,
      node_exporter_port_ref: nil,
      status: :stopped,
      primary_interface_ip: nil
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{node_exporter_port_ref: port} = state) do
    # Handle output from node_exporter - just log it at debug level
    Logger.debug("node_exporter output: #{String.trim(data)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{node_exporter_port_ref: port} = state) do
    Logger.warning("node_exporter port exited with status: #{status}")

    new_state = %{state |
      node_exporter_pid: nil,
      node_exporter_port: nil,
      node_exporter_port_ref: nil,
      status: :stopped,
      primary_interface_ip: nil
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    # Ignore exits from other processes
    {:noreply, state}
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
      stop_node_exporter(state.node_exporter_pid, state.node_exporter_port_ref)
    end

    :ok
  end

  ## Private Functions

  defp start_node_exporter(state) do
    if File.exists?(@node_exporter_binary) do
      # Build command arguments for node_exporter
      args = [
        "--web.listen-address=#{state.listen_address}:#{state.port}",
        "--path.procfs=#{@host_proc_path}",
        "--path.sysfs=#{@host_sys_path}",
        "--path.rootfs=#{@host_root_path}",
        "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)",
        "--collector.netdev.device-exclude=^(veth.*|docker.*|br-.*|lo)$$",
        "--no-collector.ipvs"
      ]

      Logger.debug("Starting node_exporter with args: #{inspect(args)}")

      # Start the process in the background
      case spawn_node_exporter(args) do
        {:ok, pid, port_ref} ->
          {:ok, pid, state.port, port_ref}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :node_exporter_not_found}
    end
  rescue
    error ->
      Logger.error("Exception starting node_exporter: #{inspect(error)}")
      {:error, {:exception, error}}
  end

  defp spawn_node_exporter(args) do
    try do
      # Use Port to spawn the process
      port = Port.open({:spawn_executable, @node_exporter_binary}, [
        :binary,
        :stderr_to_stdout,
        args: args,
        cd: "/tmp"
      ])

      # Give the process a moment to start
      :timer.sleep(2000)

      # Find the actual PID of the node_exporter process
      case find_node_exporter_process(@metrics_port) do
        {:ok, pid} ->
          {:ok, pid, port}

        {:error, reason} ->
          Port.close(port)
          {:error, {:process_not_found, reason}}
      end
    rescue
      error ->
        {:error, {:spawn_failed, error}}
    end
  end

  defp stop_node_exporter(nil, nil), do: :ok
  defp stop_node_exporter(nil, port_ref) when is_port(port_ref) do
    Port.close(port_ref)
    :ok
  end
  defp stop_node_exporter(pid, port_ref) when is_port(port_ref) do
    Port.close(port_ref)
    stop_node_exporter(pid, nil)
  end

  defp stop_node_exporter(pid, _port_ref) when is_pid(pid) do
    if Process.alive?(pid) do
      Process.exit(pid, :shutdown)
      :ok
    else
      :ok
    end
  end

  defp stop_node_exporter(pid, _port_ref) when is_integer(pid) do
    try do
      case System.cmd("kill", ["-TERM", "#{pid}"], stderr_to_stdout: true) do
        {_output, 0} ->
          :ok

        {output, _exit_code} ->
          Logger.warning("Failed to kill node_exporter process #{pid}: #{output}")
          # Try force kill
          case System.cmd("kill", ["-KILL", "#{pid}"], stderr_to_stdout: true) do
            {_output, 0} -> :ok
            {output, _exit_code} -> {:error, {:kill_failed, output}}
          end
      end
    rescue
      error -> {:error, {:exception, error}}
    end
  end

  defp find_node_exporter_process(port) do
    case System.cmd("pgrep", ["-f", "node_exporter.*#{port}"], stderr_to_stdout: true) do
      {pid_string, 0} ->
        case Integer.parse(String.trim(pid_string)) do
          {pid, ""} -> {:ok, pid}
          _ -> {:error, :invalid_pid}
        end

      {_output, _exit_code} ->
        {:error, :process_not_found}
    end
  rescue
    error -> {:error, {:exception, error}}
  end

  defp process_exists?(pid) when is_integer(pid) do
    case System.cmd("kill", ["-0", "#{pid}"], stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp detect_primary_interface_ip do
    # Try multiple methods to detect the primary interface IP
    detect_via_ip_route() ||
    detect_via_default_route() ||
    detect_via_interfaces()
  end

  defp detect_via_ip_route do
    case System.cmd("ip", ["route", "get", "8.8.8.8"], stderr_to_stdout: true) do
      {output, 0} ->
        # Parse output like: "8.8.8.8 via 192.168.1.1 dev eth0 src 192.168.1.100 uid 1000"
        case Regex.run(~r/src\s+(\d+\.\d+\.\d+\.\d+)/, output) do
          [_, ip] -> ip
          _ -> nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp detect_via_default_route do
    case System.cmd("ip", ["route", "show", "default"], stderr_to_stdout: true) do
      {output, 0} ->
        # Parse output like: "default via 192.168.1.1 dev eth0 proto dhcp src 192.168.1.100 metric 100"
        case Regex.run(~r/dev\s+(\w+)/, output) do
          [_, interface] ->
            get_interface_ip(interface)

          _ ->
            nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp detect_via_interfaces do
    case System.cmd("ip", ["addr", "show"], stderr_to_stdout: true) do
      {output, 0} ->
        # Find the first non-loopback, non-docker interface with an IP
        output
        |> String.split("\n")
        |> Enum.find_value(&extract_ip_from_line/1)

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp get_interface_ip(interface) do
    case System.cmd("ip", ["addr", "show", interface], stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.run(~r/inet\s+(\d+\.\d+\.\d+\.\d+)/, output) do
          [_, ip] -> ip
          _ -> nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp extract_ip_from_line(line) do
    case Regex.run(~r/inet\s+(\d+\.\d+\.\d+\.\d+)\/\d+.+scope global/, line) do
      [_, ip] when ip != "127.0.0.1" -> ip
      _ -> nil
    end
  end

  defp build_config do
    %{
      port: @metrics_port,
      listen_address: @listen_address,
      binary_path: @node_exporter_binary,
      host_proc_path: @host_proc_path,
      host_sys_path: @host_sys_path,
      host_root_path: @host_root_path
    }
  end
end
