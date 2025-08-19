defmodule EdgeAdmin.Repo.Migrations.ChangeNodeIdToString do
  @moduledoc false
  use Ecto.Migration

  def change do
    drop unique_index(:nodes, [:hardware_id])

    alter table(:nodes) do
      remove :hardware_id, :string
    end
  end
end
