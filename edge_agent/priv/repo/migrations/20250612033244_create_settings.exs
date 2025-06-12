defmodule EdgeAgent.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    create table(:settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :value, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:settings, [:key])
  end
end
