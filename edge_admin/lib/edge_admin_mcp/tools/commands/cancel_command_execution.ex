# edge_admin/lib/edge_admin_mcp/tools/commands/cancel_command_execution.ex
defmodule EdgeAdminMcp.Tools.Commands.CancelCommandExecution do
  @moduledoc """
  Cancel a command execution.

  Behaviour by status:

  - `pending` → cancelled immediately. Status set to `cancelled`,
    `cancelled_at` set to now. Output and exit_code stay nil.
    Returns `%{result: "execution cancelled"}`.
  - `sent` → cancellation request forwarded to the agent. Best-effort
    and async — re-fetch the execution later to see whether the agent
    actually stopped before completing. Returns
    `%{result: "cancellation request sent"}`.
  - `completed` / `cancelled` / `expired` → returns a 409-style conflict
    error; only `pending` and `sent` are cancellable.
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
