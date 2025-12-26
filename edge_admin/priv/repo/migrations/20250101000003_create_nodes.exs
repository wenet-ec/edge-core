defmodule EdgeAdmin.Repo.Migrations.CreateNodes do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:nodes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cluster_id, references(:clusters, type: :binary_id, on_delete: :restrict), null: false

      # Informative fields
      add :id_type, :string, null: false
      add :status, :string, null: false, default: "healthy"
      add :last_seen_at, :utc_datetime
      add :version, :string, null: false

      # Operational fields
      add :http_port, :integer, null: false
      add :ssh_port, :integer, null: false
      add :host_metrics_port, :integer, null: false
      add :wireguard_metrics_port, :integer, null: false
      add :http_proxy_port, :integer, null: false
      add :socks5_proxy_port, :integer, null: false
      add :api_token, :string, null: false
      add :proxy_password, :string, null: false
      add :self_update_enabled, :boolean, null: false, default: false

      # Netmaker references
      add :netmaker_host_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create unique_index(:nodes, [:api_token])
    create index(:nodes, [:cluster_id])
    create index(:nodes, [:id_type])
    create index(:nodes, [:status])
    create index(:nodes, [:last_seen_at])
  end
end
