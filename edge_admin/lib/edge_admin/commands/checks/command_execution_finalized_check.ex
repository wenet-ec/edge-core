# edge_admin/lib/edge_admin/commands/checks/command_execution_finalized_check.ex
defmodule EdgeAdmin.Commands.Checks.CommandExecutionFinalizedCheck do
  @moduledoc "Checks that an execution can no longer receive an Agent result."

  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @spec check(CommandExecution.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%CommandExecution{} = execution) do
    if CommandExecution.finalized?(execution) do
      :ok
    else
      {:error, {:conflict, "cannot delete execution with status '#{execution.status}' until it is finalized"}}
    end
  end
end
