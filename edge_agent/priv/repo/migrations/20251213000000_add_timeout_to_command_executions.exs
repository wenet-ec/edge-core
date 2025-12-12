defmodule EdgeAgent.Repo.Migrations.AddTimeoutToCommandExecutions do
  use Ecto.Migration

  def change do
    alter table(:command_executions) do
      add :timeout, :integer, comment: "Command timeout in milliseconds, null means no timeout"
    end
  end
end
