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

  @doc "Builds the complete local execution row sent to Admin."
  @spec build_report_params(CommandExecution.t()) :: map()
  def build_report_params(execution) do
    %{
      id: execution.id,
      command_id: execution.command_id,
      node_id: execution.node_id,
      command_text: execution.command_text,
      timeout: execution.timeout,
      expires_at: format_datetime(execution.expires_at),
      status: Atom.to_string(execution.status),
      output: CommandExecutionOutput.truncate(execution.output),
      exit_code: execution.exit_code,
      completed_at: format_datetime(execution.completed_at),
      inserted_at: format_datetime(execution.inserted_at),
      updated_at: format_datetime(execution.updated_at)
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
