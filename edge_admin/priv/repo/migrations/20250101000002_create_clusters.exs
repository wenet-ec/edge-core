defmodule EdgeAdmin.Repo.Migrations.CreateClusters do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:clusters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :ipv4_range, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:clusters, [:name])
    create unique_index(:clusters, [:ipv4_range])
  end
end
