# edge_admin/lib/edge_admin/commands/schemas/command.ex
defmodule EdgeAdmin.Commands.Schemas.Command do
  @moduledoc false
  use EdgeAdmin.Schema

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.Commands.Schemas.CommandExecution

  @type t :: %__MODULE__{
          id: String.t(),
          command_text: String.t(),
          timeout: integer() | nil,
          expired_at: DateTime.t() | nil,
          targeting: map(),
          command_executions: [CommandExecution.t()] | NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @derive {
    Flop.Schema,
    filterable: [:command_text, :timeout, :expired_at, :inserted_at, :updated_at],
    sortable: [:timeout, :expired_at, :inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  schema "commands" do
    # Maps to TEXT in database
    field(:command_text, :string)
    field(:timeout, :integer)
    field(:expired_at, :utc_datetime)
    field(:targeting, :map)

    # Associations
    has_many(:command_executions, CommandExecution, on_delete: :delete_all)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(command, attrs) do
    command
    |> cast(attrs, [:command_text, :timeout, :expired_at, :targeting])
    |> validate_required([:command_text, :targeting])
    |> validate_command_text_format()
    |> validate_timeout()
    |> validate_expired_at()
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
  defp validate_expired_at(changeset) do
    validate_change(changeset, :expired_at, fn :expired_at, expired_at ->
      if DateTime.after?(expired_at, DateTime.utc_now()) do
        []
      else
        [expired_at: "must be in the future"]
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
