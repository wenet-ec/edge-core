defmodule EdgeAdmin.Repo.Migrations.CreateNodes do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:nodes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cluster_id, references(:clusters, type: :binary_id, on_delete: :restrict), null: false

      add :enrollment_key_id,
          references(:enrollment_keys, type: :binary_id, on_delete: :nilify_all)

      add :status, :string,
        null: false,
        default: "healthy"

      add :last_seen_at, :utc_datetime
      add :version, :string, null: false

      # Operational fields
      add :http_port, :integer,
        null: false,
        check: %{name: "nodes_http_port_valid", expr: "http_port BETWEEN 1 AND 65535"}

      add :ssh_port, :integer, null: false, check: %{name: "nodes_ssh_port_valid", expr: "ssh_port BETWEEN 1 AND 65535"}

      add :agent_metrics_port, :integer,
        null: false,
        default: 44_000,
        check: %{name: "nodes_agent_metrics_port_valid", expr: "agent_metrics_port BETWEEN 1 AND 65535"}

      add :host_metrics_port, :integer,
        null: false,
        check: %{name: "nodes_host_metrics_port_valid", expr: "host_metrics_port BETWEEN 1 AND 65535"}

      add :wireguard_metrics_port, :integer,
        null: false,
        check: %{name: "nodes_wireguard_metrics_port_valid", expr: "wireguard_metrics_port BETWEEN 1 AND 65535"}

      add :http_proxy_port, :integer,
        null: false,
        check: %{name: "nodes_http_proxy_port_valid", expr: "http_proxy_port BETWEEN 1 AND 65535"}

      add :socks5_proxy_port, :integer,
        null: false,
        check: %{name: "nodes_socks5_proxy_port_valid", expr: "socks5_proxy_port BETWEEN 1 AND 65535"}

      add :api_token, :string, null: false
      add :proxy_password, :string, null: false
      add :recovery_key, :string
      add :self_update_enabled, :boolean, null: false, default: false

      # Netmaker references
      add :vpn_host_id, :binary_id, null: false

      timestamps(type: :utc_datetime)
    end

    if repo().__adapter__() == Ecto.Adapters.Postgres do
      create constraint(:nodes, :nodes_http_port_valid, check: "http_port BETWEEN 1 AND 65535")
      create constraint(:nodes, :nodes_ssh_port_valid, check: "ssh_port BETWEEN 1 AND 65535")
      create constraint(:nodes, :nodes_agent_metrics_port_valid, check: "agent_metrics_port BETWEEN 1 AND 65535")
      create constraint(:nodes, :nodes_host_metrics_port_valid, check: "host_metrics_port BETWEEN 1 AND 65535")

      create constraint(:nodes, :nodes_wireguard_metrics_port_valid,
               check: "wireguard_metrics_port BETWEEN 1 AND 65535"
             )

      create constraint(:nodes, :nodes_http_proxy_port_valid, check: "http_proxy_port BETWEEN 1 AND 65535")
      create constraint(:nodes, :nodes_socks5_proxy_port_valid, check: "socks5_proxy_port BETWEEN 1 AND 65535")
    end

    create unique_index(:nodes, [:api_token])
    create unique_index(:nodes, [:recovery_key])
    create index(:nodes, [:cluster_id])
    create index(:nodes, [:enrollment_key_id])
    create index(:nodes, [:status])
    create index(:nodes, [:last_seen_at])
  end
end
