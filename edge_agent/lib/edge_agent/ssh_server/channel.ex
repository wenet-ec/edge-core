# edge_agent/lib/edge_agent/ssh_server/channel.ex
defmodule EdgeAgent.SshServer.Channel do
  @moduledoc """
  SSH channel handler for shell sessions.
  Implements the :ssh_server_channel behavior.
  """

  @behaviour :ssh_server_channel

  alias EdgeAgent.Settings

  require Logger

  @bashrc_path "/usr/local/bin/edge_bashrc"

  @impl true
  def init(_options) do
    {:ok, %{start_time: System.monotonic_time(:millisecond)}}
  end

  @impl true
  def handle_msg({:ssh_channel_up, channel_id, connection_ref}, state) do
    Logger.debug("SSH channel up: #{channel_id}")

    # Emit connection telemetry
    :telemetry.execute(
      [:edge_agent, :ssh, :connection],
      %{count: 1, total: 1},
      %{result: :success}
    )

    {:ok, Map.merge(state, %{channel_id: channel_id, connection_ref: connection_ref})}
  end

  @impl true
  def handle_msg({port, {:data, data}}, %{port: port, connection_ref: conn_ref, channel_id: ch_id} = state) do
    # Forward port output to SSH client
    :ssh_connection.send(conn_ref, ch_id, data)
    {:ok, state}
  end

  @impl true
  def handle_msg({port, {:exit_status, status}}, %{port: port, connection_ref: conn_ref, channel_id: ch_id} = state) do
    Logger.info("Shell exited with status: #{status}")
    :ssh_connection.exit_status(conn_ref, ch_id, status)
    :ssh_connection.send_eof(conn_ref, ch_id)
    {:stop, ch_id, state}
  end

  @impl true
  def handle_msg({:EXIT, port, reason}, %{port: port} = state) do
    Logger.info("Port exited: #{inspect(reason)}")
    {:ok, state}
  end

  @impl true
  def handle_msg(msg, state) do
    Logger.debug("Received message: #{inspect(msg)}")
    {:ok, state}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _connection_ref, {:data, _channel_id, _type, data}}, state) do
    # Forward client input to bash port
    if Map.has_key?(state, :port) do
      Port.command(state.port, data)
    end

    {:ok, state}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, connection_ref, {:pty, channel_id, want_reply, _pty_opts}}, state) do
    Logger.debug("PTY requested")
    :ssh_connection.reply_request(connection_ref, want_reply, :success, channel_id)
    {:ok, state}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, connection_ref, {:shell, channel_id, want_reply}}, state) do
    Logger.info("Shell requested")
    :ssh_connection.reply_request(connection_ref, want_reply, :success, channel_id)

    # Get node ID for prompt
    node_id = get_node_id()

    # Get authenticated username from connection
    username = get_authenticated_user(connection_ref)
    Logger.info("Starting shell for user: #{username}")

    # Use script to allocate a PTY, then run bash
    port =
      Port.open({:spawn_executable, "/usr/bin/script"}, [
        {:args,
         [
           "-qfc",
           "/bin/bash --rcfile #{@bashrc_path} -i",
           "/dev/null"
         ]},
        {:env,
         [
           {~c"TERM", ~c"xterm"},
           {~c"EDGE_NODE_ID", to_charlist(node_id)},
           {~c"USER", to_charlist(username)}
         ]},
        :binary,
        :use_stdio,
        :exit_status,
        :stderr_to_stdout
      ])

    {:ok, Map.merge(state, %{port: port, connection_ref: connection_ref, channel_id: channel_id})}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _connection_ref, {:eof, _channel_id}}, state) do
    Logger.debug("EOF received from client")

    if Map.has_key?(state, :port) do
      Port.close(state.port)
    end

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
    # Emit session duration telemetry
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
    # Get connection info to extract the authenticated username
    case :ssh.connection_info(connection_ref, :user) do
      {:user, user} when is_list(user) ->
        to_string(user)

      _ ->
        "unknown"
    end
  rescue
    _ -> "unknown"
  end
end
