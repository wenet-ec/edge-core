# edge_admin/lib/edge_admin_web/controllers/commands/command_execution_json.ex
defmodule EdgeAdminWeb.Controllers.Commands.CommandExecutionJSON do
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, command_executions: command_executions, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(command_executions, &data/1), flop_meta)
  end

  def show(%{conn: conn, command_execution: command_execution}) do
    ResponseEnvelope.success(conn, data(command_execution))
  end

  def cancel(%{conn: conn, result: result}) do
    ResponseEnvelope.success(conn, result)
  end

  defp data(%CommandExecution{} = command_execution) do
    %{
      id: command_execution.id,
      command_id: command_execution.command_id,
      node_id: command_execution.node_id,
      cluster_name: CommandExecution.cluster_name(command_execution),
      target_all: command_execution.target_all,
      status: command_execution.status,
      command_text: CommandExecution.command_text(command_execution),
      timeout: CommandExecution.timeout(command_execution),
      output: command_execution.output,
      exit_code: command_execution.exit_code,
      sent_at: command_execution.sent_at,
      completed_at: command_execution.completed_at,
      cancelled_at: command_execution.cancelled_at,
      expired_at: CommandExecution.expired_at(command_execution),
      inserted_at: command_execution.inserted_at,
      updated_at: command_execution.updated_at
    }
  end
end
