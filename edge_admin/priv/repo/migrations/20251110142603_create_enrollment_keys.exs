defmodule EdgeAdmin.Repo.Migrations.CreateEphemeralEnrollmentKeys do
  use Ecto.Migration

  def change do
    create table(:ephemeral_enrollment_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token, :string, null: false
      add :cluster_id, references(:clusters, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ephemeral_enrollment_keys, [:token])
    create index(:ephemeral_enrollment_keys, [:cluster_id])
  end
end
