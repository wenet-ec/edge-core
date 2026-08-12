# edge_admin/lib/edge_admin/commands/checks/command_execution_accepts_result_check.ex
defmodule EdgeAdmin.Commands.Checks.CommandExecutionAcceptsResultCheck do
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

  ## Paired predicate

  This is the layer-3 early-409 gate against the struct in hand. The same
  predicate is encoded in SQL inside `EdgeAdmin.Commands.transition_to_result/2`
  as the WHERE clause of a conditional UPDATE, where it defends against
  concurrent writers (peer admin races, agent retries hitting a different
  admin) that the struct-level check cannot see. If you change the predicate
  here, change the dynamic there too — the two layers must agree.
  """

  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @doc "Checks whether an execution may accept a result from an Agent."
  @spec check(CommandExecution.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%CommandExecution{status: :sent}), do: :ok

  def check(%CommandExecution{status: :cancelled, exit_code: nil}), do: :ok

  def check(%CommandExecution{status: :expired, exit_code: nil}), do: :ok

  # A dropped execution belongs to a deleted node. It must never accept a
  # result, including if the former agent retries after deletion.
  def check(%CommandExecution{status: :dropped}), do: {:error, {:conflict, "execution is no longer active"}}

  def check(%CommandExecution{status: status, exit_code: exit_code}) do
    {:error, {:conflict, "execution is in '#{status}' status (exit_code: #{inspect(exit_code)}) and cannot be updated"}}
  end
end
