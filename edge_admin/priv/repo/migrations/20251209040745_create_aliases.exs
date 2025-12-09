defmodule EdgeAdmin.Repo.Migrations.CreateAliases do
  use Ecto.Migration

  def change do
    create table(:aliases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :node_id, references(:nodes, type: :binary_id, on_delete: :delete_all), null: false
      add :cluster_id, references(:clusters, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:aliases, [:cluster_id, :name])
    create index(:aliases, [:node_id])
  end
end
