defmodule EdgeAdmin.Repo.Migrations.CreateCommands do
  use Ecto.Migration

  def change do
    create table(:commands, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :command_text, :text

      timestamps(type: :utc_datetime)
    end
  end
end
