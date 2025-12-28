defmodule EdgeAdmin.Repo.Migrations.CreateSshPublicKeys do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:ssh_public_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ssh_username_id, references(:ssh_usernames, type: :binary_id, on_delete: :delete_all), null: false
      add :public_key, :text, null: false
      add :key_name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ssh_public_keys, [:ssh_username_id, :key_name],
             name: :ssh_public_keys_ssh_username_id_key_name_index
           )
  end
end
