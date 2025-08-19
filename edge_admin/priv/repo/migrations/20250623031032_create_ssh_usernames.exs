defmodule EdgeAdmin.Repo.Migrations.CreateSshUsernames do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:ssh_usernames, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :username, :string
      add :node_id, references(:nodes, on_delete: :delete_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:ssh_usernames, [:node_id])
    create unique_index(:ssh_usernames, [:node_id, :username])
  end
end
