# edge_admin/lib/edge_admin/commands/command.ex
defmodule EdgeAdmin.Commands.Command do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "commands" do
    # Maps to TEXT in database
    field(:command_text, :string)

    # Associations
    has_many(:command_executions, EdgeAdmin.Commands.CommandExecution, on_delete: :delete_all)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(command, attrs) do
    command
    |> cast(attrs, [:command_text])
    |> validate_required([:command_text])
    |> validate_command_text_format()
  end

  @doc false
  defp validate_command_text_format(changeset) do
    validate_change(changeset, :command_text, fn :command_text, command_text ->
      trimmed = String.trim(command_text)

      if trimmed == "" do
        [command_text: "cannot be empty or only whitespace"]
      else
        []
      end
    end)
  end
end
