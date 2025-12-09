defmodule EdgeAdmin.Repo.Migrations.UpdateNodesSchema do
  @moduledoc false
  use Ecto.Migration

  import Ecto.Query
  alias EdgeAdmin.Repo

  def up do
    # Add new fields
    alter table(:nodes) do
      add :cluster_id, references(:clusters, type: :binary_id, on_delete: :restrict), null: false
      add :netmaker_host_id, :binary_id
      add :http_port, :integer, null: false
      add :ssh_port, :integer, null: false
      add :metrics_port, :integer, null: false
      add :http_proxy_port, :integer, null: false
      add :socks5_proxy_port, :integer, null: false
      add :api_token, :string
      add :proxy_password, :string
      add :version, :string
      add :self_update_enabled, :boolean, default: false
    end

    flush()

    # Update id_type values using Ecto
    from(n in "nodes", where: n.id_type in ["machine_id", "hardware_id"])
    |> Repo.update_all(set: [id_type: "persistent"])

    from(n in "nodes", where: n.id_type == "temporary_id")
    |> Repo.update_all(set: [id_type: "random"])

    # Set default status for existing records
    from(n in "nodes", where: is_nil(n.status))
    |> Repo.update_all(set: [status: "healthy"])

    # Modify timestamp columns
    alter table(:nodes) do
      modify :inserted_at, :utc_datetime, from: :naive_datetime
      modify :updated_at, :utc_datetime, from: :naive_datetime
    end

    # Drop old index first
    drop_if_exists unique_index(:nodes, [:hardware_id])

    # Remove old fields
    alter table(:nodes) do
      remove :vpn_ip
    end

    # Add new indexes
    create unique_index(:nodes, [:api_token])
    create index(:nodes, [:cluster_id])
  end

  def down do
    # Add back old fields
    alter table(:nodes) do
      add :vpn_ip, :string
    end

    # Recreate old index
    create unique_index(:nodes, [:hardware_id])

    # Drop new indexes
    drop_if_exists unique_index(:nodes, [:api_token])
    drop_if_exists index(:nodes, [:cluster_id])

    flush()

    # Revert id_type values using Ecto
    from(n in "nodes", where: n.id_type == "persistent")
    |> Repo.update_all(set: [id_type: "machine_id"])

    from(n in "nodes", where: n.id_type == "random")
    |> Repo.update_all(set: [id_type: "temporary_id"])

    # Revert timestamp columns
    alter table(:nodes) do
      modify :inserted_at, :naive_datetime, from: :utc_datetime
      modify :updated_at, :naive_datetime, from: :utc_datetime
    end

    # Remove new fields
    alter table(:nodes) do
      remove :cluster_id
      remove :netmaker_host_id
      remove :http_port
      remove :ssh_port
      remove :metrics_port
      remove :http_proxy_port
      remove :socks5_proxy_port
      remove :api_token
      remove :proxy_password
      remove :version
      remove :self_update_enabled
    end
  end
end
