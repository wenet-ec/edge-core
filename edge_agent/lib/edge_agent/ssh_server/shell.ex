# edge_agent/lib/edge_agent/ssh_server/shell.ex
defmodule EdgeAgent.SshServer.Shell do
  @moduledoc """
  Manages the SSH shell interface.
  """

  require Logger

  def create_shell_function do
    fn user, peer_addr ->
      Logger.info("SSH shell started for user: #{user}, peer: #{inspect(peer_addr)}")
      edge_shell()
    end
  end

  def edge_shell do
    spawn(fn ->
      Process.flag(:trap_exit, true)
      IO.puts("Edge Shell - Type 'quit' to exit")
      shell_loop()
    end)
  end

  def shell_loop do
    case IO.gets("edge> ") do
      :eof ->
        :ok

      {:error, _reason} ->
        shell_loop()

      input ->
        command = input |> to_string() |> String.trim()

        case command do
          "" ->
            shell_loop()

          cmd when cmd in ["quit", "exit"] ->
            IO.puts("Goodbye!")
            :ok

          _ ->
            execute_hostscript_command(command)
            shell_loop()
        end
    end
  end

  defp execute_hostscript_command(command) do
    case System.cmd("/usr/local/bin/hostscript", [command], stderr_to_stdout: true) do
      {output, 0} ->
        IO.puts(output)

      {output, exit_code} ->
        IO.puts(output)
        IO.puts("Command exited with code: #{exit_code}")
    end
  rescue
    error ->
      IO.puts("Error executing command: #{inspect(error)}")
  end
end
