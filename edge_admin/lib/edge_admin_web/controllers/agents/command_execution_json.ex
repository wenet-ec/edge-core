# edge_admin/lib/edge_admin_web/controllers/agents/command_execution_json.ex
defmodule EdgeAdminWeb.Controllers.Agents.CommandExecutionJSON do
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, command_executions: command_executions, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(command_executions, &data/1), flop_meta)
  end

  def show(%{conn: conn, command_execution: command_execution}) do
    ResponseEnvelope.success(conn, data(command_execution))
  end

  defp data(%CommandExecution{} = execution) do
    %{
      id: execution.id,
      command_id: execution.command_id,
      command_text: CommandExecution.command_text(execution),
      timeout: CommandExecution.timeout(execution),
      expires_at: CommandExecution.expires_at(execution),
      status: execution.status,
      inserted_at: execution.inserted_at
    }
  end
end
