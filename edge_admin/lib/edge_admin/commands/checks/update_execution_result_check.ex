# edge_admin/lib/edge_admin/commands/checks/update_execution_result_check.ex
defmodule EdgeAdmin.Commands.Checks.UpdateExecutionResultCheck do
  @moduledoc """
  Precondition check for updating a command execution result from an agent.

  An execution result can be updated when:
  - Status is "sent" (normal case)
  - Status is "completed" with exit_code 143 (race condition: execution was
    cancelled while the agent was already running it - allow the agent to
    overwrite with actual results)
  """

  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @spec check(CommandExecution.t()) :: :ok | {:error, {:conflict, String.t()}}
  # Normal case: execution is in "sent" status
  def check(%CommandExecution{status: "sent"}), do: :ok

  # Race condition: cancelled (completed with exit_code 143) but command actually ran
  def check(%CommandExecution{status: "completed", exit_code: 143}), do: :ok

  def check(%CommandExecution{status: status, exit_code: exit_code}) do
    {:error, {:conflict, "execution is in '#{status}' status (exit_code: #{inspect(exit_code)}) and cannot be updated"}}
  end
end
