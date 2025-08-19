defmodule EdgeAdmin.Repo.Migrations.AddUniqueIndexToCommandExecutions do
  @moduledoc false
  use Ecto.Migration

  def change do
    create unique_index(:command_executions, [:node_id, :command_id])
  end
end
