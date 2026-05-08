# edge_admin/lib/edge_admin/commands/checks/execution_accepts_result_check.ex
defmodule EdgeAdmin.Commands.Checks.ExecutionAcceptsResultCheck do
  @moduledoc """
  Checks that an execution is in a state that accepts a result update from an agent.

  An execution result can be updated when:
  - Status is "sent" (normal case)
  - Status is "cancelled" with nil exit_code (race condition: pending execution
    was cancelled by admin before agent ran it, but agent picked it up via sync
    and is now reporting back - allow the agent to overwrite with actual results)
  - Status is "expired" with nil exit_code (race condition: admin expired the
    execution via scheduler, but agent already picked it up and is now reporting
    back - accept the result as it reflects what actually happened on the node)
  """

  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @spec check(CommandExecution.t()) :: :ok | {:error, {:conflict, String.t()}}
  # Normal case: execution is in :sent status
  def check(%CommandExecution{status: :sent}), do: :ok

  # Race condition: pending execution was cancelled by admin, but agent already
  # picked it up and ran it - allow the agent to overwrite with actual results
  def check(%CommandExecution{status: :cancelled, exit_code: nil}), do: :ok

  # Race condition: admin expired the execution, but agent already picked it up
  # and ran it - accept the result; agent is the source of truth for what ran
  def check(%CommandExecution{status: :expired, exit_code: nil}), do: :ok

  def check(%CommandExecution{status: status, exit_code: exit_code}) do
    {:error, {:conflict, "execution is in '#{status}' status (exit_code: #{inspect(exit_code)}) and cannot be updated"}}
  end
end
