defmodule EdgeAgent.Repo.Migrations.AddCompletedAtToCommandExecutions do
  use Ecto.Migration

  def change do
    alter table(:command_executions) do
      add :completed_at, :utc_datetime
    end
  end
end
