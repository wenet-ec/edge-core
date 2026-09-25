# edge_admin/lib/edge_admin/commands/checks/non_finalized_command_executions_check.ex
defmodule EdgeAdmin.Commands.Checks.NonFinalizedCommandExecutionsCheck do
  @moduledoc "Checks that all executions for a command are finalized."

  import Ecto.Query

  alias EdgeAdmin.Commands.Enums.CommandExecutionStatuses
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Repo

  @spec check(Command.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%Command{id: command_id}) do
    active_statuses = CommandExecutionStatuses.cancellable_statuses()
    result_pending_statuses = CommandExecutionStatuses.completion_timestamp_dependent_finalization_statuses()

    count =
      Repo.one(
        from(ce in CommandExecution,
          where: ce.command_id == ^command_id,
          where:
            ce.status in ^active_statuses or
              (ce.status in ^result_pending_statuses and is_nil(ce.completed_at)),
          select: count(ce.id)
        )
      )

    if count == 0 do
      :ok
    else
      {:error,
       {:conflict,
        "cannot delete command with #{count} non-finalized execution(s) - all executions must be finalized first"}}
    end
  end
end
