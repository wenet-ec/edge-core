# edge_admin/lib/edge_admin/mcp/tools/commands/get_command_execution.ex
defmodule EdgeAdmin.MCP.Tools.Commands.GetCommandExecution do
  @moduledoc "Get a command execution by ID. Returns status, output, exit code, and timestamps."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Commands

  schema do
    field :execution_id, :string, required: true
  end

  @impl true
  def execute(%{execution_id: id}, frame) do
    case Commands.get_command_execution(id) do
      {:ok, e} ->
        {:reply,
         Response.json(Response.tool(), %{
           id: e.id,
           status: e.status,
           exit_code: e.exit_code,
           output: e.output,
           command_id: e.command_id,
           node_id: e.node_id,
           sent_at: e.sent_at,
           completed_at: e.completed_at
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "Command execution #{id} not found"), frame}
    end
  end
end
