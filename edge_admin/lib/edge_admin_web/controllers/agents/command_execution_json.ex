# edge_admin/lib/edge_admin_web/controllers/agents/command_execution_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.CommandExecutionJSON do
  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @doc """
  Renders a list of command executions.
  """
  def index(%{command_executions: command_executions}) do
    %{data: for(execution <- command_executions, do: data(execution))}
  end

  @doc """
  Renders a single command execution.
  """
  def show(%{command_execution: command_execution}) do
    %{data: data(command_execution)}
  end

  defp data(%CommandExecution{} = execution) do
    %{
      id: execution.id,
      command_id: execution.command_id,
      command_text: CommandExecution.command_text(execution),
      timeout: CommandExecution.timeout(execution),
      status: execution.status,
      inserted_at: execution.inserted_at
    }
  end
end
