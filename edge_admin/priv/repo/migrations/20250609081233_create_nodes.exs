defmodule EdgeAdmin.Repo.Migrations.CreateNodes do
  use Ecto.Migration

  def change do
    create table(:nodes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :hardware_id, :string
      add :vpn_ip, :string
      add :last_seen_at, :utc_datetime
      add :status, :string

      timestamps()
    end

    create unique_index(:nodes, [:hardware_id])
  end
end
