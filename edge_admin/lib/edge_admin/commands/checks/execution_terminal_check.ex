# edge_admin/lib/edge_admin/commands/checks/execution_terminal_check.ex
defmodule EdgeAdmin.Commands.Checks.ExecutionTerminalCheck do
  @moduledoc """
  Checks that an execution is in a terminal status (completed, cancelled, or expired).

  Prevents deletion of pending or in-flight executions.
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
