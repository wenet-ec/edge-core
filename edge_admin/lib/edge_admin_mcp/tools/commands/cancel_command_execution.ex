# edge_admin/lib/edge_admin_mcp/tools/commands/cancel_command_execution.ex
defmodule EdgeAdminMcp.Tools.Commands.CancelCommandExecution do
  @moduledoc """
  Cancel a command execution.

  - pending → cancelled immediately (status set to completed, output "Command cancelled")
  - sent → cancellation request forwarded to agent (best-effort, async — check status later)
  - completed → error, cannot cancel
  """
  use EdgeAdminMcp, :tool

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
      {:error, :not_found} ->
        {:reply, Response.json(Response.tool(), tool_error(:not_found, "Command execution #{id} not found")), frame}

      {:error, reason} ->
        {:reply, Response.json(Response.tool(), tool_error(reason)), frame}
    end
  end
end
