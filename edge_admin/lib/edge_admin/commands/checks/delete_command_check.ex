# edge_admin/lib/edge_admin/commands/checks/delete_command_check.ex
defmodule EdgeAdmin.Commands.Checks.DeleteCommandCheck do
  @moduledoc """
  Precondition check for command deletion.

  A command can only be deleted when all its executions are completed.
  This prevents cascading deletion of pending or in-flight executions.
  """

  import Ecto.Query

  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Repo

  @spec check(Command.t()) :: :ok | {:error, {:conflict, String.t()}}
  def check(%Command{id: command_id}) do
    count =
      Repo.one(
        from(ce in CommandExecution,
          where: ce.command_id == ^command_id,
          where: ce.status in ["pending", "sent"],
          select: count(ce.id)
        )
      )

    if count == 0 do
      :ok
    else
      {:error,
       {:conflict,
        "cannot delete command with #{count} non-completed execution(s) - all executions must be completed first"}}
    end
  end
end
