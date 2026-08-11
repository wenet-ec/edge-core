# edge_agent/lib/edge_agent/ssh_server/channel.ex
defmodule EdgeAgent.SshServer.Channel do
  @moduledoc """
  SSH channel handler for shell and exec sessions.

  Implements the `:ssh_server_channel` behavior. Both paths route the
  operator's commands onto the host, so the agent container behaves as a
  pure gateway:

    * `:shell` (interactive) — erlexec spawns `host_pty_spawn`, which enters
      the host's mount namespace, allocates a PTY on the host's devpts, and
      execs `bash --login -i` on it. TTY-sensitive programs (nano, less,
      top, sudo) work because they're running natively on the host.
    * `:exec` (`ssh user@host 'cmd'`) — a `Port.open` spawns `hostscript`,
      which `nsenter`s into the host namespaces and runs the command via
      `bash --login -c "..."`. No PTY needed.
  """

  @behaviour :ssh_server_channel

  alias EdgeAgent.Settings
  alias EdgeAgent.SshServer.Channel.Pty

  require Logger

  # `host_pty_spawn` arguments: namespace handle to enter (host's PID 1 mount
  # ns, reachable via the `/host` bind mount), then the shell binary and its
  # argv that gets exec'd after the namespace swap + PTY allocation. The C
  # helper itself injects `--rcfile /proc/self/fd/N` so bash sources our
  # branded prompt (memfd-backed, no on-disk file); see host_pty_spawn.c.
  @host_pty_spawn ~c"/usr/local/bin/host_pty_spawn"
  @host_ns_handle ~c"/host/proc/1/ns/mnt"
  @host_shell_argv [~c"/bin/bash", ~c"--login", ~c"-i"]

  # Conservative defaults when the client doesn't send sensible values
  # (or sends 0 for "use pixel dimensions instead", which we ignore).
  @default_rows 24
  @default_cols 80

  @impl true
  def init(_options) do
    {:ok, %{start_time: System.monotonic_time(:millisecond), pty: nil, ospid: nil}}
  end

  @impl true
  def handle_msg({:ssh_channel_up, channel_id, connection_ref}, state) do
    Logger.debug("SSH channel up: #{channel_id}")

    :telemetry.execute(
      [:edge_agent, :ssh, :connection],
      %{count: 1, total: 1},
      %{result: :success}
    )

    {:ok, Map.merge(state, %{channel_id: channel_id, connection_ref: connection_ref})}
  end

  # erlexec delivers shell output as {:stdout, OsPid, Data}
  @impl true
  def handle_msg({:stdout, ospid, data}, %{ospid: ospid, connection_ref: conn_ref, channel_id: ch_id} = state) do
    :ssh_connection.send(conn_ref, ch_id, data)
    {:ok, state}
  end

  # erlexec monitors deliver {:DOWN, OsPid, :process, _Pid, Reason}
  @impl true
  def handle_msg(
        {:DOWN, ospid, :process, _pid, reason},
        %{ospid: ospid, connection_ref: conn_ref, channel_id: ch_id} = state
      ) do
    status =
      case reason do
        :normal -> 0
        :noproc -> 0
        {:exit_status, n} when is_integer(n) -> Pty.exit_status_from_wait(n)
        _ -> 1
      end

    Logger.info("Shell exited with status: #{status} (reason: #{inspect(reason)})")
    :ssh_connection.exit_status(conn_ref, ch_id, status)
    :ssh_connection.send_eof(conn_ref, ch_id)
    {:stop, ch_id, %{state | ospid: nil}}
  end

  # Output from the exec-path Port (hostscript)
  @impl true
  def handle_msg({port, {:data, data}}, %{port: port, connection_ref: conn_ref, channel_id: ch_id} = state) do
    :ssh_connection.send(conn_ref, ch_id, data)
    {:ok, state}
  end

  @impl true
  def handle_msg({port, {:exit_status, status}}, %{port: port, connection_ref: conn_ref, channel_id: ch_id} = state) do
    Logger.info("Exec command exited with status: #{status}")
    :ssh_connection.exit_status(conn_ref, ch_id, status)
    :ssh_connection.send_eof(conn_ref, ch_id)
    {:stop, ch_id, state}
  end

  @impl true
  def handle_msg({:EXIT, port, reason}, %{port: port, connection_ref: conn_ref, channel_id: ch_id} = state) do
    Logger.info("Port exited: #{inspect(reason)}")
    :ssh_connection.send_eof(conn_ref, ch_id)
    {:stop, ch_id, state}
  end

  @impl true
  def handle_msg(msg, state) do
    Logger.debug("Received message: #{inspect(msg)}")
    {:ok, state}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _connection_ref, {:data, _channel_id, _type, data}}, state) do
    cond do
      is_integer(state.ospid) ->
        :exec.send(state.ospid, data)

      Map.has_key?(state, :port) ->
        Port.command(state.port, data)

      true ->
        :ok
    end

    {:ok, state}
  end

  # The client requested a pty. Save its parameters; we'll allocate the real
  # PTY when the client follows up with :shell (or :exec, if a tty was asked
  # for). RFC 4254 §6.2: on success, reply :success and just hold the info.
  @impl true
  def handle_ssh_msg(
        {:ssh_cm, connection_ref, {:pty, channel_id, want_reply, {term, char_w, row_h, pix_w, pix_h, modes}}},
        state
      ) do
    Logger.debug(
      "PTY requested: term=#{inspect(term)} char_w=#{char_w} row_h=#{row_h} pix_w=#{pix_w} pix_h=#{pix_h} modes=#{length(modes)}"
    )

    pty = %{
      term: Pty.pty_term(term),
      cols: Pty.nonzero_or(char_w, @default_cols),
      rows: Pty.nonzero_or(row_h, @default_rows),
      pix_w: pix_w,
      pix_h: pix_h,
      modes: Pty.sanitize_pty_modes(modes)
    }

    :ssh_connection.reply_request(connection_ref, want_reply, :success, channel_id)
    {:ok, %{state | pty: pty}}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _connection_ref, {:window_change, _channel_id, w, h, _pw, _ph}}, %{ospid: ospid} = state)
      when is_integer(ospid) do
    case :exec.winsz(ospid, h, w) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.debug("winsz failed: #{inspect(reason)}")
    end

    pty =
      case state.pty do
        nil -> nil
        p -> %{p | cols: w, rows: h}
      end

    {:ok, %{state | pty: pty}}
  end

  def handle_ssh_msg({:ssh_cm, _connection_ref, {:window_change, _channel_id, _w, _h, _pw, _ph}}, state) do
    {:ok, state}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, connection_ref, {:exec, channel_id, want_reply, command}}, state) do
    Logger.info("Exec requested: #{inspect(command)}")
    :ssh_connection.reply_request(connection_ref, want_reply, :success, channel_id)

    cmd_string = to_string(command)

    port =
      Port.open({:spawn_executable, "/usr/local/bin/hostscript"}, [
        {:args, [cmd_string]},
        {:env, [{~c"HOME", ~c"/root"}, {~c"PATH", ~c"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"}]},
        {:cd, "/root"},
        :binary,
        :use_stdio,
        :exit_status,
        :stderr_to_stdout
      ])

    {:ok, Map.merge(state, %{port: port, connection_ref: connection_ref, channel_id: channel_id})}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, connection_ref, {:shell, channel_id, want_reply}}, state) do
    Logger.info("Shell requested")
    :ssh_connection.reply_request(connection_ref, want_reply, :success, channel_id)

    node_id = get_node_id()
    username = get_authenticated_user(connection_ref)
    Logger.info("Starting shell for user: #{username}")

    pty = state.pty || %{term: Pty.pty_term(nil), cols: @default_cols, rows: @default_rows, modes: []}
    env = Pty.build_shell_env(pty, username, node_id)
    cmd = [@host_pty_spawn, @host_ns_handle | @host_shell_argv]
    run_opts = Pty.build_shell_run_opts(pty, env)

    case :exec.run(cmd, run_opts) do
      {:ok, _epid, ospid} ->
        Logger.debug("Spawned host shell on pty, ospid=#{ospid}")

        {:ok,
         state
         |> Map.put(:connection_ref, connection_ref)
         |> Map.put(:channel_id, channel_id)
         |> Map.put(:ospid, ospid)}

      {:error, reason} ->
        Logger.error("Failed to spawn shell: #{inspect(reason)}")
        :ssh_connection.exit_status(connection_ref, channel_id, 127)
        :ssh_connection.send_eof(connection_ref, channel_id)
        {:stop, channel_id, state}
    end
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _connection_ref, {:eof, _channel_id}}, state) do
    Logger.debug("EOF received from client")
    # See the previous implementation's note: for non-interactive exec, the
    # client sends EOF right after the command, and prematurely closing the
    # port causes the child to be killed before producing output. For an
    # interactive PTY shell, EOF from the client is rare and we let bash
    # exit on its own when the user types `exit` or Ctrl-D.
    {:ok, state}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _connection_ref, {:exit_signal, channel_id, _, _error, _}}, state) do
    Logger.debug("Exit signal for channel #{channel_id}")
    {:stop, channel_id, state}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _connection_ref, {:exit_status, channel_id, status}}, state) do
    Logger.debug("Exit status #{status} for channel #{channel_id}")
    {:stop, channel_id, state}
  end

  @impl true
  def handle_ssh_msg(msg, state) do
    Logger.debug("Unhandled SSH message: #{inspect(msg)}")
    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    if is_integer(state[:ospid]) do
      _ = :exec.stop(state.ospid)
    end

    if Map.has_key?(state, :start_time) do
      duration = System.monotonic_time(:millisecond) - state.start_time

      :telemetry.execute(
        [:edge_agent, :ssh, :session, :duration],
        %{duration: duration},
        %{}
      )
    end

    :ok
  end

  defp get_node_id do
    case Settings.get_node_id() do
      nil -> "unknown"
      node_id -> node_id
    end
  rescue
    _ -> "unknown"
  end

  defp get_authenticated_user(connection_ref) do
    case :ssh.connection_info(connection_ref, :user) do
      {:user, user} when is_list(user) -> to_string(user)
      _ -> "unknown"
    end
  rescue
    _ -> "unknown"
  end
end
