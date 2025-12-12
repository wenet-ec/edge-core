defmodule EdgeAdmin.Repo.Migrations.AddTimeoutToCommands do
  use Ecto.Migration

  def change do
    alter table(:commands) do
      add :timeout, :integer, comment: "Command timeout in milliseconds, null means no timeout"
    end
  end
end
