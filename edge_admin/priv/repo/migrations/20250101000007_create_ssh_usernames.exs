defmodule EdgeAdmin.Repo.Migrations.CreateSshUsernames do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:ssh_usernames, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :node_id, references(:nodes, type: :binary_id, on_delete: :delete_all), null: false
      add :username, :string, null: false
      add :password_hash, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ssh_usernames, [:node_id, :username], name: :ssh_usernames_node_id_username_index)
  end
end
