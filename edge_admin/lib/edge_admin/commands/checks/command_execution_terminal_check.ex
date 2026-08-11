# edge_admin/lib/edge_admin/commands/checks/execution_terminal_check.ex
defmodule EdgeAdmin.Commands.Checks.CommandExecutionTerminalCheck do
  @moduledoc """
  Checks that an execution is in a terminal status (completed, cancelled, expired, or dropped).

  Prevents deletion of pending or in-flight executions.
  """

  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @doc "Checks whether an execution is in a terminal state."
  @spec check(CommandExecution.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%CommandExecution{} = execution) do
    if CommandExecution.terminal?(execution) do
      :ok
    else
      {:error,
       {:conflict,
        "cannot delete execution with status '#{execution.status}' - only completed, cancelled, expired, or dropped executions can be deleted"}}
    end
  end
end
