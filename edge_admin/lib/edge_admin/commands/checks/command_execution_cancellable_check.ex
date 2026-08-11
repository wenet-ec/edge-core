# edge_admin/lib/edge_admin/commands/checks/command_execution_cancellable_check.ex
defmodule EdgeAdmin.Commands.Checks.CommandExecutionCancellableCheck do
  @moduledoc """
  Checks that an execution is in a cancellable status (pending or sent).

  Completed, cancelled, expired, and dropped executions cannot be cancelled.
  """

  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @doc "Checks whether an execution may be cancelled."
  @spec check(CommandExecution.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%CommandExecution{} = execution) do
    if CommandExecution.cancellable?(execution) do
      :ok
    else
      {:error,
       {:conflict,
        "cannot cancel execution with status '#{execution.status}' - only 'pending' or 'sent' executions can be cancelled"}}
    end
  end
end
