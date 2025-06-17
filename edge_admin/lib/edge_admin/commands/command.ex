# edge_admin/lib/edge_admin/commands/command.ex
defmodule EdgeAdmin.Commands.Command do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "commands" do
    field :commands, {:array, :string}

    # Associations
    has_many :command_executions, EdgeAdmin.Commands.CommandExecution

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(command, attrs) do
    command
    |> cast(attrs, [:commands])
    |> validate_required([:commands])
    |> validate_length(:commands, min: 1, message: "must have at least one command")
    |> validate_commands_format()
  end

  @doc false
  defp validate_commands_format(changeset) do
    validate_change(changeset, :commands, fn :commands, commands ->
      if Enum.all?(commands, &is_binary/1) and Enum.all?(commands, &(String.trim(&1) != "")) do
        []
      else
        [commands: "all commands must be non-empty strings"]
      end
    end)
  end
end
