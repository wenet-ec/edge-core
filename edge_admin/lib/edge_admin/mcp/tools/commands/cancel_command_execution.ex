# edge_admin/lib/edge_admin/mcp/tools/commands/cancel_command_execution.ex
defmodule EdgeAdmin.MCP.Tools.Commands.CancelCommandExecution do
  @moduledoc """
  Cancel a command execution.

  - pending → cancelled immediately (status set to completed, output "Command cancelled")
  - sent → cancellation request forwarded to agent (best-effort, async — check status later)
  - completed → error, cannot cancel
  """
  use EdgeAdmin.MCP, :tool

  alias EdgeAdmin.Commands

  schema do
    field :execution_id, {:required, :string}
  end

  @impl true
  def execute(%{execution_id: id}, frame) do
    with {:ok, execution} <- Commands.get_command_execution(id),
         {:ok, result} <- Commands.cancel_command_execution(execution) do
      {:reply, Response.json(Response.tool(), result), frame}
    else
      {:error, :not_found} -> {:reply, Response.error(Response.tool(), "Command execution #{id} not found"), frame}
      {:error, reason} -> {:reply, Response.error(Response.tool(), "Cancel failed: #{inspect(reason)}"), frame}
    end
  end
end
