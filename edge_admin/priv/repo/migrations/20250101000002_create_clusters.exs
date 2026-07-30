defmodule EdgeAdmin.Repo.Migrations.CreateClusters do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:clusters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :ipv4_range, :string, null: false
      add :ipv6_range, :string, null: false

      add :node_limit, :integer,
        null: true,
        check: %{name: "clusters_node_limit_positive", expr: "node_limit IS NULL OR node_limit > 0"}

      add :deleted_at, :utc_datetime, null: true

      timestamps(type: :utc_datetime)
    end

    if repo().__adapter__() == Ecto.Adapters.Postgres do
      create constraint(:clusters, :clusters_node_limit_positive, check: "node_limit IS NULL OR node_limit > 0")
    end

    create unique_index(:clusters, [:name])
    create unique_index(:clusters, [:ipv4_range])
    create unique_index(:clusters, [:ipv6_range])
  end
end
