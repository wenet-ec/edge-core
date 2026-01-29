defmodule EdgeAdmin.Repo.Migrations.CreateNodeMetricsCache do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:node_metrics_cache, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :node_id, references(:nodes, type: :binary_id, on_delete: :delete_all), null: false
      add :metrics_type, :string, null: false
      add :metrics_text, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:node_metrics_cache, [:node_id, :metrics_type],
             name: :node_metrics_cache_node_id_metrics_type_index
           )

    create index(:node_metrics_cache, [:node_id])
    create index(:node_metrics_cache, [:updated_at])
  end
end
