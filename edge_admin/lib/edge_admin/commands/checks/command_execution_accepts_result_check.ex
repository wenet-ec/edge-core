# edge_admin/lib/edge_admin/commands/checks/command_execution_accepts_result_check.ex
defmodule EdgeAdmin.Commands.Checks.CommandExecutionAcceptsResultCheck do
  @moduledoc """
  Checks that an execution is in a state that accepts a result update from an agent.

  An execution result can be updated when:
  - Status is "pending" (Admin did not record delivery acknowledgement, but
    the authenticated owning Agent's result proves it received and ran the
    execution)
  - Status is "sent" (normal case)
  - Status is "cancelled" with nil Admin-owned `completed_at` (race condition: pending execution
    was cancelled by admin before agent ran it, but agent picked it up via sync
    and is now reporting back - allow the agent to overwrite with actual results)
  - Status is "expired" with nil Admin-owned `completed_at` (race condition: admin expired the
    execution via scheduler, but agent already picked it up and is now reporting
    back - accept the result as it reflects what actually happened on the node)

  ## Paired predicate

  This is the layer-3 early-409 gate against the struct in hand. The same
  predicate is encoded in the conditional SQL update in
  `EdgeAdmin.Commands.Workflows.CommandExecutionLifecycle`, where it defends
  against concurrent writers (peer admin races, agent retries hitting a
  different admin) that the struct-level check cannot see. If you change the
  predicate here, change the SQL condition there too — the two layers must
  agree.
  """

  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @spec check(CommandExecution.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%CommandExecution{} = execution) do
    if CommandExecution.finalized?(execution) do
      {:error,
       {:conflict,
        "execution is finalized with status '#{execution.status}' (completed_at: #{inspect(execution.completed_at)})"}}
    else
      :ok
    end
  end
end
