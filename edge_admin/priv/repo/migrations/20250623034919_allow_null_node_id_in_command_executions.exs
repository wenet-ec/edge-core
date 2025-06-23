defmodule EdgeAdmin.Repo.Migrations.AllowNullNodeIdInCommandExecutions do
  use Ecto.Migration

  def change do
    alter table(:command_executions) do
      modify(:node_id, :binary_id, null: true)
    end
  end
end
