# edge_admin/lib/edge_admin/mcp/tools/commands/delete_command_execution.ex
defmodule EdgeAdmin.MCP.Tools.Commands.DeleteCommandExecution do
  @moduledoc "Delete a command execution. Only completed executions can be deleted."
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Commands

  schema do
    field :execution_id, :string, required: true
  end

  @impl true
  def execute(%{execution_id: id}, frame) do
    with {:ok, execution} <- Commands.get_command_execution(id),
         {:ok, _} <- Commands.delete_command_execution(execution) do
      {:reply, Response.text(Response.tool(), "Command execution #{id} deleted"), frame}
    else
      {:error, :not_found} -> {:reply, Response.error(Response.tool(), "Command execution #{id} not found"), frame}
      {:error, reason} -> {:reply, Response.error(Response.tool(), "Delete failed: #{inspect(reason)}"), frame}
    end
  end
end
