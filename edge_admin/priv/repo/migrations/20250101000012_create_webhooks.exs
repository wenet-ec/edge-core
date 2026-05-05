defmodule EdgeAdmin.Repo.Migrations.CreateWebhooks do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:webhooks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :url, :string, null: false
      add :secret, :binary, null: false
      add :headers, :binary
      add :subscribed_events, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime)
    end
  end
end
