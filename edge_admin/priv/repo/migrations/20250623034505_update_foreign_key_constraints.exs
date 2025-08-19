defmodule EdgeAdmin.Repo.Migrations.UpdateForeignKeyConstraints do
  @moduledoc false
  use Ecto.Migration

  def up do
    # Drop existing foreign key constraints
    drop(constraint(:command_executions, "command_executions_command_id_fkey"))
    drop(constraint(:command_executions, "command_executions_node_id_fkey"))

    # Recreate with proper cascade behavior
    alter table(:command_executions) do
      modify(:command_id, references(:commands, on_delete: :delete_all, type: :binary_id))
      modify(:node_id, references(:nodes, on_delete: :nilify_all, type: :binary_id))
    end
  end

  def down do
    # Drop the new constraints
    drop(constraint(:command_executions, "command_executions_command_id_fkey"))
    drop(constraint(:command_executions, "command_executions_node_id_fkey"))

    # Restore original constraints (on_delete: :nothing)
    alter table(:command_executions) do
      modify(:command_id, references(:commands, on_delete: :nothing, type: :binary_id))
      modify(:node_id, references(:nodes, on_delete: :nothing, type: :binary_id))
    end
  end
end
