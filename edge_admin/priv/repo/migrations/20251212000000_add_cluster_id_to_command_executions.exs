defmodule EdgeAdmin.Repo.Migrations.AddClusterIdToCommandExecutions do
  use Ecto.Migration

  def change do
    alter table(:command_executions) do
      add :cluster_id, references(:clusters, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:command_executions, [:cluster_id])
  end
end
