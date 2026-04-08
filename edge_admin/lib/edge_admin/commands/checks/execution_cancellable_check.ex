# edge_admin/lib/edge_admin/commands/checks/execution_cancellable_check.ex
defmodule EdgeAdmin.Commands.Checks.ExecutionCancellableCheck do
  @moduledoc """
  Checks that an execution is in a cancellable status (pending or sent).

  Completed, cancelled, and expired executions cannot be cancelled.
  """

  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @spec check(CommandExecution.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%CommandExecution{status: status}) when status in ["pending", "sent"], do: :ok

  def check(%CommandExecution{status: status}) do
    {:error,
     {:conflict,
      "cannot cancel execution with status '#{status}' - only 'pending' or 'sent' executions can be cancelled"}}
  end
end
