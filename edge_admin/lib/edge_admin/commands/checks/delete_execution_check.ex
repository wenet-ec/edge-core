# edge_admin/lib/edge_admin/commands/checks/delete_execution_check.ex
defmodule EdgeAdmin.Commands.Checks.DeleteExecutionCheck do
  @moduledoc """
  Precondition check for command execution deletion.

  An execution can only be deleted when it is completed.
  This prevents deleting pending or in-flight executions.
  """

  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @spec check(CommandExecution.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%CommandExecution{status: status}) when status in ["completed", "cancelled", "expired"], do: :ok

  def check(%CommandExecution{status: status}) do
    {:error,
     {:conflict,
      "cannot delete execution with status '#{status}' - only completed, cancelled, or expired executions can be deleted"}}
  end
end
