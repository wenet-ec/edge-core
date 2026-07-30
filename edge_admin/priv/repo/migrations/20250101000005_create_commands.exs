defmodule EdgeAdmin.Repo.Migrations.CreateCommands do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:commands, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :command_text, :text,
        null: false,
        check: %{name: "commands_command_text_present", expr: "length(trim(command_text)) > 0"}

      add :timeout, :integer, check: %{name: "commands_timeout_positive", expr: "timeout IS NULL OR timeout > 0"}
      add :expires_at, :utc_datetime
      add :targeting, :map, null: false

      timestamps(type: :utc_datetime)
    end

    if repo().__adapter__() == Ecto.Adapters.Postgres do
      create constraint(:commands, :commands_command_text_present, check: "length(trim(command_text)) > 0")

      create constraint(:commands, :commands_timeout_positive, check: "timeout IS NULL OR timeout > 0")
    end
  end
end
