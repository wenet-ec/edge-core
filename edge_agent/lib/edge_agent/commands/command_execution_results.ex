# edge_agent/lib/edge_agent/commands/command_execution_results.ex
defmodule EdgeAgent.Commands.CommandExecutionResults do
  @moduledoc "Pure result classification and reporting payload builders."

  alias EdgeAgent.Commands.CommandExecutionOutput
  alias EdgeAgent.Commands.Schemas.CommandExecution

  @doc "Maps a host command exit code to the local execution result category."
  @spec categorize_exit_code(integer()) :: :success | :timeout | :cancelled | :failure | :unknown
  def categorize_exit_code(exit_code) do
    cond do
      exit_code == 0 -> :success
      exit_code == 124 -> :timeout
      exit_code == 143 -> :cancelled
      exit_code > 0 -> :failure
      true -> :unknown
    end
  end

  @doc "Builds the wire payload sent to Admin for a completed execution."
  @spec build_report_params(CommandExecution.t()) :: map()
  def build_report_params(execution) do
    %{
      status: Atom.to_string(execution.status),
      output: CommandExecutionOutput.truncate(execution.output),
      exit_code: execution.exit_code,
      completed_at: execution.completed_at && DateTime.to_iso8601(execution.completed_at)
    }
  end
end
