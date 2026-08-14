# edge_admin/lib/edge_admin/commands/checks/pending_command_executions_check.ex
defmodule EdgeAdmin.Commands.Checks.PendingCommandExecutionsCheck do
  @moduledoc """
  Checks that a command has no pending or in-flight executions.

  Prevents deletion of a command while executions are still running.
  """

  import Ecto.Query

  alias EdgeAdmin.Commands.Enums.CommandExecutionStatuses
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Repo

  @doc "Ensures a command has no pending or in-flight executions."
  @spec check(Command.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%Command{id: command_id}) do
    cancellable = CommandExecutionStatuses.cancellable_statuses()

    count =
      Repo.one(
        from(ce in CommandExecution,
          where: ce.command_id == ^command_id,
          where: ce.status in ^cancellable,
          select: count(ce.id)
        )
      )

    if count == 0 do
      :ok
    else
      {:error,
       {:conflict,
        "cannot delete command with #{count} non-terminal execution(s) - all executions must be terminal first"}}
    end
  end
end
