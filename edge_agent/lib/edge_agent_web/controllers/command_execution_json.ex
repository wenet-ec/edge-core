# edge_agent/lib/edge_agent_web/controllers/command_execution_json.ex
defmodule EdgeAgentWeb.Controllers.CommandExecutionJSON do
  alias EdgeAgent.Commands.CommandExecution

  @doc """
  Renders a single command_execution.
  """
  def show(%{command_execution: command_execution}) do
    %{data: data(command_execution)}
  end

  defp data(%CommandExecution{} = command_execution) do
    %{
      id: command_execution.id,
      command_id: command_execution.command_id,
      node_id: command_execution.node_id,
      command_text: command_execution.command_text,
      status: command_execution.status,
      output: command_execution.output,
      exit_code: command_execution.exit_code,
      inserted_at: command_execution.inserted_at,
      updated_at: command_execution.updated_at
    }
  end
end
