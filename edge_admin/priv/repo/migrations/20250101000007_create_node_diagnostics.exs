defmodule EdgeAdmin.Repo.Migrations.CreateNodeDiagnostics do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:node_diagnostics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :node_id, references(:nodes, type: :binary_id, on_delete: :delete_all), null: false
      add :report, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:node_diagnostics, [:node_id], name: :node_diagnostics_node_id_index)
  end
end
