# edge_admin/lib/edge_admin_mcp/tools/commands/cancel_command_execution.ex
defmodule EdgeAdminMcp.Tools.Commands.CancelCommandExecution do
  @moduledoc """
  Cancel a command execution.

  Behaviour by status:

  - `pending` → cancelled immediately. Status set to `cancelled`,
    `cancelled_at` set to now. Output and exit_code stay nil.
    Returns the cancelled execution.
  - `sent` → cancellation request forwarded to the agent. Best-effort
    and async — re-fetch the execution later to see whether the agent
    actually stopped before completing. Returns `%{cancellation: "accepted"}`.
  - `completed` / `cancelled` / `expired` / `dropped` → returns a 409-style conflict
    error; only `pending` and `sent` are cancellable.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Commands
  alias EdgeAdmin.Commands.Views.CommandExecutionView

  @impl true
  def title, do: "Cancel Command Execution"
  @impl true
  def annotations, do: %{"destructiveHint" => true, "idempotentHint" => false, "openWorldHint" => false}

  schema do
    field :execution_id, {:required, :string}
  end

  @impl true
  def execute(%{execution_id: id}, frame) do
    with {:ok, execution} <- Commands.get_command_execution(id),
         {:ok, result} <- Commands.cancel_command_execution(execution) do
      case result do
        {:cancelled, execution} ->
          {:reply, Response.json(Response.tool(), CommandExecutionView.render(execution)), frame}

        :accepted ->
          {:reply, Response.json(Response.tool(), %{cancellation: "accepted"}), frame}
      end
    else
      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Command execution #{id} not found"), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
