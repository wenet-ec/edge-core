# edge_admin/lib/edge_admin/commands/checks/cancel_execution_check.ex
defmodule EdgeAdmin.Commands.Checks.CancelExecutionCheck do
  @moduledoc """
  Precondition check for command execution cancellation.

  An execution can only be cancelled when it is pending or sent.
  Completed executions cannot be cancelled.
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
