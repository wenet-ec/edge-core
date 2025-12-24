defmodule EdgeAdmin.Repo.Migrations.AddTargetingToCommands do
  use Ecto.Migration

  def change do
    alter table(:commands) do
      add :targeting, :map, null: false
    end
  end
end
