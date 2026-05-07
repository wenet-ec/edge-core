# edge_admin/lib/edge_admin_web/controllers/commands/command_execution_json.ex
defmodule EdgeAdminWeb.Controllers.Commands.CommandExecutionJSON do
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdminWeb.ResponseEnvelope

  def index(%{conn: conn, command_executions: command_executions, meta: flop_meta}) do
    ResponseEnvelope.success(conn, Enum.map(command_executions, &CommandExecution.to_public/1), flop_meta)
  end

  def show(%{conn: conn, command_execution: command_execution}) do
    ResponseEnvelope.success(conn, CommandExecution.to_public(command_execution))
  end

  def cancel(%{conn: conn, result: result}) do
    ResponseEnvelope.success(conn, result)
  end
end
