# edge_admin/lib/edge_admin/commands/command.ex
defmodule EdgeAdmin.Commands.Command do
  @moduledoc false
  use EdgeAdmin.Schema

  @derive {
    Flop.Schema,
    filterable: [:command_text, :inserted_at],
    sortable: [:inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  schema "commands" do
    # Maps to TEXT in database
    field(:command_text, :string)
    field(:timeout, :integer)
    field(:targeting, :map)

    # Associations
    has_many(:command_executions, EdgeAdmin.Commands.CommandExecution, on_delete: :delete_all)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(command, attrs) do
    command
    |> cast(attrs, [:command_text, :timeout, :targeting])
    |> validate_required([:command_text, :targeting])
    |> validate_command_text_format()
    |> validate_timeout()
  end

  @doc false
  defp validate_timeout(changeset) do
    validate_change(changeset, :timeout, fn :timeout, timeout ->
      cond do
        is_nil(timeout) ->
          # Timeout is optional - nil is valid
          []

        timeout <= 0 ->
          [timeout: "must be a positive number (in milliseconds)"]

        true ->
          []
      end
    end)
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
