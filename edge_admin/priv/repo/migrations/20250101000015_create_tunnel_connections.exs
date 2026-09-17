# edge_admin/priv/repo/migrations/20250101000015_create_tunnel_connections.exs
defmodule EdgeAdmin.Repo.Migrations.CreateTunnelConnections do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:tunnel_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :tunnel_client_id,
          references(:tunnel_clients, type: :binary_id, on_delete: :delete_all),
          null: false

      add :node_id, references(:nodes, type: :binary_id, on_delete: :delete_all), null: false
      add :tunnel_ipv4_address, :string, null: false
      add :tunnel_ipv6_address, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tunnel_connections, [:tunnel_client_id, :node_id])
    create unique_index(:tunnel_connections, [:node_id, :tunnel_ipv4_address])
    create unique_index(:tunnel_connections, [:node_id, :tunnel_ipv6_address])
  end
end
