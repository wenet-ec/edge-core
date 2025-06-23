defmodule EdgeAdmin.Repo.Migrations.CreateSshPublicKeys do
  use Ecto.Migration

  def change do
    create table(:ssh_public_keys, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:public_key, :text)
      add(:key_name, :string)
      add(:ssh_username_id, references(:ssh_usernames, on_delete: :delete_all, type: :binary_id))

      timestamps(type: :utc_datetime)
    end

    create(index(:ssh_public_keys, [:ssh_username_id]))
    create(unique_index(:ssh_public_keys, [:ssh_username_id, :key_name]))
  end
end
