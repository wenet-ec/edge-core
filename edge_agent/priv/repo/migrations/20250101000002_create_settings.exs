defmodule EdgeAgent.Repo.Migrations.CreateSettings do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :key, :string,
        null: false,
        check: %{name: "settings_key_present", expr: "length(trim(key)) > 0"}

      add :value, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:settings, [:key])
  end
end
