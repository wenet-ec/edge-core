defmodule EdgeAdmin.Repo.Migrations.CreateEnrollmentKeys do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:enrollment_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cluster_id, references(:clusters, type: :binary_id, on_delete: :delete_all), null: false
      add :key, :text, null: false
      add :uses_remaining, :integer, null: true, default: 1
      add :expired_at, :utc_datetime, null: true
      add :last_used_at, :utc_datetime, null: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:enrollment_keys, [:key])
    create index(:enrollment_keys, [:cluster_id])
  end
end
