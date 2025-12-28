# edge_admin/lib/edge_admin/commands/rules/deletion_rules.ex
defmodule EdgeAdmin.Commands.Rules.DeletionRules do
  @moduledoc """
  Business rules for command and execution deletion.

  These rules enforce domain constraints to maintain data integrity
  and prevent deletion of active/in-flight commands and executions.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Repo

  @doc """
  Validates that a command can be deleted.

  Only commands where ALL executions are completed can be deleted.
  This prevents cascading deletion of pending or sent executions.

  ## Returns
  - `:ok` - Command can be deleted
  - `{:error, changeset}` - Command cannot be deleted (has non-completed executions)
  """
  def validate_command_deletion(%Command{id: command_id}) do
    # Query to count non-completed executions
    non_completed_count =
      Repo.one(
        from(ce in CommandExecution,
          where: ce.command_id == ^command_id,
          where: ce.status in ["pending", "sent"],
          select: count(ce.id)
        )
      )

    if non_completed_count == 0 do
      :ok
    else
      changeset =
        %Command{id: command_id}
        |> change()
        |> add_error(
          :base,
          "cannot delete command with #{non_completed_count} non-completed execution(s) - all executions must be completed first"
        )

      {:error, changeset}
    end
  end

  @doc """
  Validates that a command execution can be deleted.

  Only completed executions can be deleted to prevent data loss
  for pending or in-flight commands.

  ## Returns
  - `:ok` - Execution can be deleted
  - `{:error, changeset}` - Execution cannot be deleted (not completed)
  """
  def validate_execution_deletion(%CommandExecution{status: "completed"}) do
    :ok
  end

  def validate_execution_deletion(%CommandExecution{status: status} = execution) do
    changeset =
      execution
      |> change()
      |> add_error(
        :status,
        "cannot delete execution with status '#{status}' - only completed executions can be deleted"
      )

    {:error, changeset}
  end
end
