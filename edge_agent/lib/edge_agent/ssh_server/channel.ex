# edge_agent/lib/edge_agent/ssh_server/channel.ex
defmodule EdgeAgent.SshServer.Channel do
  @moduledoc """
  SSH channel handler for shell and exec sessions.

  Implements the `:ssh_server_channel` behavior. The shell path spawns a
  login bash on a real PTY via erlexec so that TTY-sensitive programs
  (nano, less, top, sudo) behave correctly. The exec path runs commands
  through `hostscript` (nsenter into the host namespaces) without a PTY,
  matching how non-interactive `ssh user@host 'cmd'` is expected to work.
  """

  @behaviour :ssh_server_channel

  alias EdgeAgent.Settings

  require Bitwise
  require Logger

  # The SSH shell runs container-side bash sourced with `edge_bashrc`. That
  # rcfile sets up host-routing: a curated list of admin commands (docker,
  # systemctl, ip, …) become wrapper functions that call `hostscript <cmd>`,
  # and any unknown command falls through `command_not_found_handle` which
  # also forwards to hostscript. So `nano /etc/foo` from the SSH prompt runs
  # the host's nano against the host's filesystem under nsenter — the agent
  # container is the gateway, not the target.
  @bashrc_path "/usr/local/bin/edge_bashrc"

  # Conservative defaults when the client doesn't send sensible values
  # (or sends 0 for "use pixel dimensions instead", which we ignore).
  @default_term ~c"xterm"
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
        {:exit_status, n} when is_integer(n) -> exit_status_from_wait(n)
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
      term: pty_term(term),
      cols: nonzero_or(char_w, @default_cols),
      rows: nonzero_or(row_h, @default_rows),
      pix_w: pix_w,
      pix_h: pix_h,
      modes: sanitize_pty_modes(modes)
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

    pty = state.pty || %{term: @default_term, cols: @default_cols, rows: @default_rows, modes: []}
    env = build_shell_env(pty, username, node_id)
    cmd = ~c"/bin/bash --rcfile " ++ to_charlist(@bashrc_path) ++ ~c" -i"
    run_opts = build_shell_run_opts(pty, env)

    case :exec.run(cmd, run_opts) do
      {:ok, _epid, ospid} ->
        Logger.debug("Spawned bash on pty, ospid=#{ospid}")

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

  @doc false
  @spec build_shell_env(map(), String.t(), String.t()) :: [{charlist(), charlist()}]
  def build_shell_env(pty, username, node_id) do
    [
      {~c"TERM", pty.term},
      {~c"EDGE_NODE_ID", to_charlist(node_id)},
      {~c"USER", to_charlist(username)},
      {~c"HOME", ~c"/root"},
      {~c"SHELL", ~c"/bin/bash"},
      {~c"LANG", ~c"en_US.UTF-8"},
      {~c"PATH", ~c"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"}
    ]
  end

  @doc false
  @spec build_shell_run_opts(map(), [{charlist(), charlist()}]) :: keyword()
  def build_shell_run_opts(pty, env) do
    [
      {:pty, pty.modes},
      :pty_echo,
      :stdin,
      {:stdout, self()},
      {:stderr, :stdout},
      {:winsz, {pty.rows, pty.cols}},
      {:env, env},
      {:cd, ~c"/root"},
      :monitor,
      :kill_group
    ]
  end

  @doc false
  @spec pty_term(term()) :: charlist()
  def pty_term(""), do: @default_term
  def pty_term(term) when is_list(term) and term != [], do: term
  def pty_term(term) when is_binary(term) and byte_size(term) > 0, do: to_charlist(term)
  def pty_term(_), do: @default_term

  @doc false
  @spec nonzero_or(term(), pos_integer()) :: pos_integer()
  def nonzero_or(0, default), do: default
  def nonzero_or(n, _default) when is_integer(n) and n > 0, do: n
  def nonzero_or(_, default), do: default

  @doc false
  @spec sanitize_pty_modes(term()) :: [{atom(), integer() | boolean()}]
  # erlexec only accepts pty modes whose key is an atom and whose value is a
  # boolean or integer. The Erlang ssh app gives us {atom, integer} for
  # known opcodes and {byte, integer} for unknown ones (numeric opcodes).
  # Drop the numeric-opcode entries so erlexec's strict validation doesn't
  # reject the whole list.
  def sanitize_pty_modes(modes) when is_list(modes) do
    Enum.filter(modes, fn
      {k, v} when is_atom(k) and (is_integer(v) or is_boolean(v)) -> true
      _ -> false
    end)
  end

  def sanitize_pty_modes(_), do: []

  @doc false
  @spec exit_status_from_wait(integer()) :: 0..255
  # Translate erlexec's wait(2) status (e.g. 256 for "exited with status 1")
  # into a plain exit code. erlexec passes the raw status through; SSH wants
  # 0..255. If the low 7 bits are zero the child exited normally and the exit
  # code lives in the high byte; otherwise the child was killed by signal N
  # (low 7 bits = N), which we surface as a plain N.
  def exit_status_from_wait(n) when is_integer(n) do
    if Bitwise.band(n, 0x7F) == 0 do
      n |> Bitwise.bsr(8) |> Bitwise.band(0xFF)
    else
      Bitwise.band(n, 0x7F)
    end
  end
end
