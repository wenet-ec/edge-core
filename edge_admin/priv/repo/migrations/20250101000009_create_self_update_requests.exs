defmodule EdgeAdmin.Repo.Migrations.CreateSelfUpdateRequests do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:self_update_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :targeting, :map, null: false
      add :status, :string, null: false, default: "pending"
      add :summary, :map

      timestamps(type: :utc_datetime)
    end

    create index(:self_update_requests, [:status])
    create index(:self_update_requests, [:inserted_at])
  end
end
