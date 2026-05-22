# edge_agent/lib/edge_agent_web/controllers/command_execution_json.ex
defmodule EdgeAgentWeb.Controllers.CommandExecutionJSON do
  alias EdgeAgent.Commands.Schemas.CommandExecution
  alias EdgeAgentWeb.ResponseEnvelope

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
      command_text: command_execution.command_text,
      timeout: command_execution.timeout,
      expires_at: command_execution.expires_at,
      status: Atom.to_string(command_execution.status),
      output: command_execution.output,
      exit_code: command_execution.exit_code,
      inserted_at: command_execution.inserted_at,
      updated_at: command_execution.updated_at
    }
  end
end
