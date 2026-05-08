# edge_admin/lib/edge_admin/commands/checks/execution_pending_check.ex
defmodule EdgeAdmin.Commands.Checks.ExecutionPendingCheck do
  @moduledoc """
  Checks that an execution is in `:pending` status.

  Required before acknowledgment, which transitions the execution from `:pending` to `:sent`.
  """

  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @spec check(CommandExecution.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%CommandExecution{status: :pending}), do: :ok

  def check(%CommandExecution{status: status}) do
    {:error, {:conflict, "execution is in '#{status}' status and cannot be acknowledged (must be 'pending')"}}
  end
end
