defmodule EdgeAgent.Repo.Migrations.CreateCommandExecutions do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:command_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :command_id, :binary_id
      add :node_id, :binary_id
      add :command_text, :text
      add :status, :string
      add :output, :text
      add :exit_code, :integer

      timestamps(type: :utc_datetime)
    end
  end
end
