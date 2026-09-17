# edge_admin/priv/repo/migrations/20250101000014_create_tunnel_clients.exs
defmodule EdgeAdmin.Repo.Migrations.CreateTunnelClients do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:tunnel_clients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :public_key, :string, null: false
      add :private_key, :binary, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tunnel_clients, [:public_key])
  end
end
