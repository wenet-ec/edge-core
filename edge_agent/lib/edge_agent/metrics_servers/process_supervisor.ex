# edge_agent/lib/edge_agent/metrics_servers/process_supervisor.ex
defmodule EdgeAgent.MetricsServers.ProcessSupervisor do
  @moduledoc """
  Manages the node_exporter and wireguard_exporter process lifecycle.

  Handles starting, stopping, and monitoring the external
  node_exporter and wireguard_exporter processes.
  """

  alias EdgeAgent.MetricsServers.Config

  require Logger

  # `pid` here is an OS-level integer PID discovered by port after the
  # Port.open spawn (`ss -tlnp` primary, anchored `pgrep -f` fallback —
  # see `discover_pid_by_port/3`), not an Erlang `pid()`. `port` is the
  # Erlang port reference used to read stdout/stderr from the child.
  @type process_result :: {:ok, integer(), port()} | {:error, term()}
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

  @spec stop_node_exporter(integer() | nil, port() | nil) :: stop_result()
  def stop_node_exporter(nil, nil), do: :ok

  def stop_node_exporter(nil, port_ref) when is_port(port_ref) do
    Port.close(port_ref)
    :ok
  end

  def stop_node_exporter(pid, port_ref) when is_port(port_ref) do
    Port.close(port_ref)
    stop_node_exporter(pid, nil)
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
    discover_pid_by_port(port, "node_exporter", node_exporter_pgrep_pattern(port))
  end

  @spec start_wireguard_exporter() :: process_result()
  def start_wireguard_exporter do
    if File.exists?(Config.wireguard_exporter_binary()) do
      args = Config.wireguard_exporter_args()
      Logger.debug("Starting wireguard_exporter with args: #{inspect(args)}")

      case spawn_wireguard_exporter(args) do
        {:ok, pid, port_ref} ->
          {:ok, pid, port_ref}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :wireguard_exporter_not_found}
    end
  rescue
    error ->
      Logger.error("Exception starting wireguard_exporter: #{inspect(error)}")
      {:error, {:exception, error}}
  end

  @spec stop_wireguard_exporter(integer() | nil, port() | nil) :: stop_result()
  def stop_wireguard_exporter(nil, nil), do: :ok

  def stop_wireguard_exporter(nil, port_ref) when is_port(port_ref) do
    Port.close(port_ref)
    :ok
  end

  def stop_wireguard_exporter(pid, port_ref) when is_port(port_ref) do
    Port.close(port_ref)
    stop_wireguard_exporter(pid, nil)
  end

  def stop_wireguard_exporter(pid, _port_ref) when is_integer(pid) do
    case System.cmd("kill", ["-TERM", "#{pid}"], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, _exit_code} ->
        Logger.warning("Failed to kill wireguard_exporter process #{pid}: #{output}")
        # Try force kill
        case System.cmd("kill", ["-KILL", "#{pid}"], stderr_to_stdout: true) do
          {_output, 0} -> :ok
          {output, _exit_code} -> {:error, {:kill_failed, output}}
        end
    end
  rescue
    error -> {:error, {:exception, error}}
  end

  @spec find_wireguard_exporter_process(integer()) :: {:ok, integer()} | {:error, term()}
  def find_wireguard_exporter_process(port) do
    discover_pid_by_port(port, "prometheus_wireguard_exporter", wireguard_exporter_pgrep_pattern(port))
  end

  # Discover the OS PID listening on a given TCP port.
  #
  # Primary path: `ss -Htlnp sport = :PORT` queries the kernel directly and
  # returns the exact PID bound to that port — no ambiguity from cmdline
  # substring matching. Works in `pid: host` containers because `ss` reads
  # from /proc and /sys, both bind-mounted.
  #
  # Fallback: `pgrep -f PATTERN` with a flag-anchored regex tighter than the
  # original `BINARY.*PORT` form (which used to match the agent's own shell
  # commands when their argv contained both substrings). Multi-line pgrep
  # output is tolerated by taking the first valid PID.
  @spec discover_pid_by_port(integer(), String.t(), String.t()) ::
          {:ok, integer()} | {:error, term()}
  def discover_pid_by_port(port, binary_name, pgrep_pattern) do
    case discover_via_ss(port, binary_name) do
      {:ok, pid} -> {:ok, pid}
      {:error, _} -> discover_via_pgrep(pgrep_pattern)
    end
  rescue
    error -> {:error, {:exception, error}}
  end

  defp discover_via_ss(port, binary_name) do
    case System.cmd("ss", ["-Htlnp", "sport = :#{port}"], stderr_to_stdout: true) do
      {output, 0} -> parse_ss_output(output, binary_name)
      {_output, _exit_code} -> {:error, :ss_failed}
    end
  rescue
    # `ss` missing → ErlangError :enoent. Fall through to pgrep.
    _ -> {:error, :ss_unavailable}
  end

  defp discover_via_pgrep(pattern) do
    case System.cmd("pgrep", ["-f", pattern], stderr_to_stdout: true) do
      {pid_string, 0} -> parse_pgrep_output(pid_string)
      {_output, _exit_code} -> {:error, :process_not_found}
    end
  rescue
    error -> {:error, {:exception, error}}
  end

  @doc false
  # Public for unit testing. Parses one line of `ss -Htlnp` output, e.g.:
  #   LISTEN 0  128  0.0.0.0:49100  0.0.0.0:*  users:(("node_exporter",pid=8348,fd=3))
  # Returns the PID whose process name matches `binary_name`. Defends
  # against the (rare) case where multiple sockets share the port by
  # filtering on process name; the configured exporter must be one of them.
  @spec parse_ss_output(String.t(), String.t()) :: {:ok, integer()} | {:error, term()}
  def parse_ss_output(output, binary_name) do
    # Note: `ss` truncates process names to 15 chars (Linux /proc/PID/comm
    # limit), so e.g. "prometheus_wireguard_exporter" appears as
    # "prometheus_wire". Match by prefix.
    truncated = String.slice(binary_name, 0, 15)

    output
    |> String.split("\n", trim: true)
    |> Enum.find_value(fn line ->
      case Regex.run(~r/users:\(\("([^"]+)",pid=(\d+)/, line) do
        [_, proc, pid_str] ->
          if proc == truncated or proc == binary_name do
            case Integer.parse(pid_str) do
              {pid, ""} -> {:ok, pid}
              _ -> nil
            end
          end

        _ ->
          nil
      end
    end)
    |> case do
      {:ok, _} = ok -> ok
      _ -> {:error, :not_found}
    end
  end

  @doc false
  # Public for unit testing. Parses pgrep's multi-line output. The original
  # implementation required exactly one line via `Integer.parse(...)` + `""`
  # remainder match, which broke when pgrep matched both the exporter and
  # something whose cmdline incidentally contained the same substring
  # (notably the agent's own shell calls in `pid: host` mode). Now we take
  # the first parseable integer line.
  @spec parse_pgrep_output(String.t()) :: {:ok, integer()} | {:error, term()}
  def parse_pgrep_output(pid_string) do
    pid_string
    |> String.split("\n", trim: true)
    |> Enum.find_value(fn line ->
      case Integer.parse(String.trim(line)) do
        {pid, ""} -> {:ok, pid}
        _ -> nil
      end
    end)
    |> case do
      {:ok, _} = ok -> ok
      _ -> {:error, :invalid_pid}
    end
  end

  @doc false
  # Public for unit testing. Builds a flag-anchored pgrep pattern that won't
  # match shell commands containing the binary name + port as separate
  # substrings.
  @spec node_exporter_pgrep_pattern(integer()) :: String.t()
  def node_exporter_pgrep_pattern(port) do
    "node_exporter --web.listen-address=[^ ]*:#{port}($| )"
  end

  @doc false
  # Public for unit testing. See `node_exporter_pgrep_pattern/1`. The
  # wireguard exporter uses `--port N` (separate args, no `=`).
  @spec wireguard_exporter_pgrep_pattern(integer()) :: String.t()
  def wireguard_exporter_pgrep_pattern(port) do
    "prometheus_wireguard_exporter --port #{port}($| )"
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
    case find_node_exporter_process(Config.host_metrics_port()) do
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

  defp spawn_wireguard_exporter(args) do
    # Use Port to spawn the process
    port =
      Port.open({:spawn_executable, Config.wireguard_exporter_binary()}, [
        :binary,
        :stderr_to_stdout,
        args: args,
        cd: "/tmp"
      ])

    # Give the process a moment to start
    :timer.sleep(2000)

    # Find the actual PID of the wireguard_exporter process
    case find_wireguard_exporter_process(Config.wireguard_metrics_port()) do
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
