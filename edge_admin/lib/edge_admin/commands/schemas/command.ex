# edge_admin/lib/edge_admin/commands/schemas/command.ex
defmodule EdgeAdmin.Commands.Schemas.Command do
  @moduledoc "Ecto schema for a command submitted for execution on edge nodes."
  use EdgeAdmin.Schema

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Nodes.Schemas.Node

  @type t :: %__MODULE__{
          id: String.t() | nil,
          command_text: String.t() | nil,
          timeout: integer() | nil,
          expires_at: DateTime.t() | nil,
          targeting: map() | nil,
          command_executions: [CommandExecution.t()] | NotLoaded.t(),
          nodes: [Node.t()] | NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @derive {
    Flop.Schema,
    filterable: [:command_text, :timeout, :expires_at, :inserted_at, :updated_at],
    sortable: [:timeout, :expires_at, :inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  schema "commands" do
    # Maps to TEXT in database
    field(:command_text, :string)
    field(:timeout, :integer)
    field(:expires_at, :utc_datetime)
    field(:targeting, :map)

    # Associations
    has_many(:command_executions, CommandExecution, on_delete: :delete_all)
    has_many(:nodes, through: [:command_executions, :node])

    timestamps(type: :utc_datetime)
  end

  @doc "Builds a changeset for creating or updating a command."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(command, attrs) do
    command
    |> cast(attrs, [:command_text, :timeout, :expires_at, :targeting])
    |> validate_required([:command_text, :targeting])
    |> validate_command_text()
    |> validate_timeout()
    |> validate_expires_at()
    |> check_constraint(:command_text, name: :commands_command_text_present)
    |> check_constraint(:timeout, name: :commands_timeout_positive)
  end

  @doc false
  defp validate_command_text(changeset) do
    validate_change(changeset, :command_text, fn :command_text, command_text ->
      if String.trim(command_text) == "" do
        [command_text: "must not be blank"]
      else
        []
      end
    end)
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
  defp validate_expires_at(changeset) do
    validate_change(changeset, :expires_at, fn :expires_at, expires_at ->
      if DateTime.after?(expires_at, DateTime.utc_now()) do
        []
      else
        [expires_at: "must be in the future"]
      end
    end)
  end
end
