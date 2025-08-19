defmodule EdgeAdmin.Repo.Migrations.CreateCommandExecutions do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:command_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :target_all, :boolean, default: false, null: false
      add :status, :string
      add :output, :text
      add :exit_code, :integer
      add :sent_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :command_id, references(:commands, on_delete: :nothing, type: :binary_id)
      add :node_id, references(:nodes, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:command_executions, [:command_id])
    create index(:command_executions, [:node_id])
    create index(:command_executions, [:status])
    create index(:command_executions, [:node_id, :status])
    create index(:command_executions, [:node_id, :inserted_at])
  end
end
