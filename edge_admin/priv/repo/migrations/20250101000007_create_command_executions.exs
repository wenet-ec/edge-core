defmodule EdgeAdmin.Repo.Migrations.CreateCommandExecutions do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:command_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :command_id, references(:commands, type: :binary_id, on_delete: :delete_all), null: false
      add :node_id, references(:nodes, type: :binary_id, on_delete: :nilify_all)
      add :cluster_id, references(:clusters, type: :binary_id, on_delete: :nilify_all)

      add :output, :text
      add :status, :string, null: false
      add :exit_code, :integer
      add :target_all, :boolean, null: false, default: false
      add :sent_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:command_executions, [:node_id, :command_id], name: :command_executions_node_id_command_id_index)
    create index(:command_executions, [:command_id])
    create index(:command_executions, [:cluster_id])
    create index(:command_executions, [:status])
    create index(:command_executions, [:sent_at])
    create index(:command_executions, [:completed_at])
  end
end
