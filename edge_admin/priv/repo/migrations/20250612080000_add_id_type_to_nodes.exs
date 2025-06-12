defmodule EdgeAdmin.Repo.Migrations.AddIdTypeToNodes do
  use Ecto.Migration

  def change do
    alter table(:nodes) do
      add :id_type, :string
    end

    # Add index for potential queries by id_type (useful for cleanup jobs)
    create index(:nodes, [:id_type])
  end
end
