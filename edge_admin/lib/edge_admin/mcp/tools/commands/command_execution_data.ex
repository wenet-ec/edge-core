# edge_admin/lib/edge_admin/mcp/tools/commands/command_execution_data.ex
defmodule EdgeAdmin.MCP.Tools.Commands.CommandExecutionData do
  @moduledoc false

  alias EdgeAdmin.Commands.Schemas.CommandExecution

  def data(%CommandExecution{} = e) do
    %{
      id: e.id,
      command_id: e.command_id,
      node_id: e.node_id,
      cluster_name: CommandExecution.cluster_name(e),
      target_all: e.target_all,
      status: e.status,
      command_text: CommandExecution.command_text(e),
      timeout: CommandExecution.timeout(e),
      output: e.output,
      exit_code: e.exit_code,
      sent_at: e.sent_at,
      completed_at: e.completed_at,
      cancelled_at: e.cancelled_at,
      expired_at: CommandExecution.expired_at(e),
      inserted_at: e.inserted_at,
      updated_at: e.updated_at
    }
  end
end
