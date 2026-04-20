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

  @impl true
  def title, do: "Cancel Command Execution"
  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => false}

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
        {:reply, error_response(:not_found, "Command execution #{id} not found"), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
