defmodule EdgeAgent.Repo.Migrations.CreateCommandExecutions do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:command_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :command_id, :binary_id, null: false
      add :node_id, :binary_id, null: false
      add :command_text, :text, null: false
      add :timeout, :integer
      add :expires_at, :utc_datetime
      add :status, :string, null: false
      add :output, :text
      add :exit_code, :integer
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:command_executions, [:id], name: :command_executions_id_index)
    create index(:command_executions, [:command_id])
    create index(:command_executions, [:node_id])
    create index(:command_executions, [:status])
    create index(:command_executions, [:completed_at])
  end
end
