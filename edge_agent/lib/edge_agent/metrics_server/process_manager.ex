# edge_agent/lib/edge_agent/metrics_server/process_manager.ex
defmodule EdgeAgent.MetricsServer.ProcessManager do
  @moduledoc """
  Manages the node_exporter process lifecycle.

  Handles starting, stopping, and monitoring the external
  node_exporter process.
  """

  alias EdgeAgent.MetricsServer.Config

  require Logger

  @type process_result :: {:ok, pid() | integer(), port()} | {:error, term()}
  @type stop_result :: :ok | {:error, term()}

  @spec start_node_exporter() :: process_result()
  def start_node_exporter do
    if File.exists?(Config.node_exporter_binary()) do
      args = Config.node_exporter_args()
      Logger.debug("Starting node_exporter with args: #{inspect(args)}")

      case spawn_node_exporter(args) do
        {:ok, pid, port_ref} ->
          {:ok, pid, port_ref}

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

  @spec stop_node_exporter(pid() | integer() | nil, port() | nil) :: stop_result()
  def stop_node_exporter(nil, nil), do: :ok

  def stop_node_exporter(nil, port_ref) when is_port(port_ref) do
    Port.close(port_ref)
    :ok
  end

  def stop_node_exporter(pid, port_ref) when is_port(port_ref) do
    Port.close(port_ref)
    stop_node_exporter(pid, nil)
  end

  def stop_node_exporter(pid, _port_ref) when is_pid(pid) do
    if Process.alive?(pid) do
      Process.exit(pid, :shutdown)
      :ok
    else
      :ok
    end
  end

  def stop_node_exporter(pid, _port_ref) when is_integer(pid) do
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

  @spec process_exists?(integer()) :: boolean()
  def process_exists?(pid) when is_integer(pid) do
    case System.cmd("kill", ["-0", "#{pid}"], stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @spec find_node_exporter_process(integer()) :: {:ok, integer()} | {:error, term()}
  def find_node_exporter_process(port) do
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

  # Private functions

  defp spawn_node_exporter(args) do
    # Use Port to spawn the process
    port =
      Port.open({:spawn_executable, Config.node_exporter_binary()}, [
        :binary,
        :stderr_to_stdout,
        args: args,
        cd: "/tmp"
      ])

    # Give the process a moment to start
    :timer.sleep(2000)

    # Find the actual PID of the node_exporter process
    case find_node_exporter_process(Config.metrics_port()) do
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
