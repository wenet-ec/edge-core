# edge_agent/lib/edge_agent/ssh_server/shell.ex
defmodule EdgeAgent.SshServer.Shell do
  @moduledoc """
  Manages the SSH shell interface with full bash integration.
  """

  alias EdgeAgent.Settings

  require Logger

  @bashrc_path "/usr/local/bin/edge_bashrc"

  def create_shell_function do
    fn user, peer_addr ->
      Logger.info("SSH shell started for user: #{user}, peer: #{inspect(peer_addr)}")
      bash_shell()
    end
  end

  def bash_shell do
    spawn(fn ->
      Process.flag(:trap_exit, true)
      run_bash()
    end)
  end

  defp run_bash do
    # Use script to allocate a PTY, then run bash
    # This is necessary for proper job control and terminal handling
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
           {~c"EDGE_NODE_ID", to_charlist(get_node_id())}
         ]},
        :binary,
        :use_stdio,
        :exit_status,
        :stderr_to_stdout
      ])

    shell_loop(port)
  rescue
    e ->
      Logger.error("Failed to start bash shell: #{inspect(e)}")
      exit(:error)
  end

  defp shell_loop(port) do
    receive do
      {^port, {:data, data}} ->
        IO.write(data)
        shell_loop(port)

      {^port, {:exit_status, status}} ->
        Logger.info("Bash shell exited with status: #{status}")
        exit(:normal)

      {:EXIT, ^port, reason} ->
        Logger.info("Bash shell process exited: #{inspect(reason)}")
        exit(:normal)

      # Handle IO protocol messages from SSH
      {:io_request, from, reply_ref, request} ->
        reply = handle_io_request(request, port)
        send(from, {:io_reply, reply_ref, reply})
        shell_loop(port)

      msg ->
        Logger.debug("Received message: #{inspect(msg)}")
        shell_loop(port)
    end
  end

  defp handle_io_request({:put_chars, _encoding, chars}, port) when is_binary(chars) do
    Logger.debug("put_chars binary: #{inspect(chars)}")
    Port.command(port, chars)
    :ok
  end

  defp handle_io_request({:put_chars, _encoding, chars}, port) when is_list(chars) do
    Logger.debug("put_chars list: #{inspect(chars)}")
    Port.command(port, IO.iodata_to_binary(chars))
    :ok
  end

  defp handle_io_request({:put_chars, _encoding, module, function, args}, port) do
    data = apply(module, function, args)
    Port.command(port, IO.iodata_to_binary(data))
    :ok
  end

  defp handle_io_request({:get_geometry, _}, _port) do
    {:ok, {80, 24}}
  end

  defp handle_io_request({:setopts, _opts}, _port) do
    :ok
  end

  defp handle_io_request(:getopts, _port) do
    {:ok, [binary: true, encoding: :unicode]}
  end

  defp handle_io_request({:requests, requests}, port) do
    Enum.each(requests, &handle_io_request(&1, port))
    :ok
  end

  defp handle_io_request(_request, _port) do
    {:error, :request}
  end

  defp get_node_id do
    # Get node ID from settings
    case Settings.get_node_id() do
      nil -> "unknown"
      node_id -> node_id
    end
  rescue
    _ -> "unknown"
  end
end
