defmodule EdgeAdmin.Repo.Migrations.AddPasswordToSshUsernames do
  use Ecto.Migration

  def change do
    alter table(:ssh_usernames) do
      add :password_hash, :string
      modify :inserted_at, :utc_datetime, from: :naive_datetime
      modify :updated_at, :utc_datetime, from: :naive_datetime
    end

    alter table(:ssh_public_keys) do
      modify :inserted_at, :utc_datetime, from: :naive_datetime
      modify :updated_at, :utc_datetime, from: :naive_datetime
    end
  end
end
