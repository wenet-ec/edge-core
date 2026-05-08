# edge_admin/lib/edge_admin/commands/checks/execution_terminal_check.ex
defmodule EdgeAdmin.Commands.Checks.ExecutionTerminalCheck do
  @moduledoc """
  Checks that an execution is in a terminal status (completed, cancelled, or expired).

  Prevents deletion of pending or in-flight executions.
  """

  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @spec check(CommandExecution.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%CommandExecution{} = execution) do
    if CommandExecution.terminal?(execution) do
      :ok
    else
      {:error,
       {:conflict,
        "cannot delete execution with status '#{execution.status}' - only completed, cancelled, or expired executions can be deleted"}}
    end
  end
end
