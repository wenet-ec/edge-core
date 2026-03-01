# edge_agent/lib/edge_agent/commands/command_execution.ex
defmodule EdgeAgent.Commands.CommandExecution do
  @moduledoc false
  use EdgeAgent.Schema

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          output: String.t() | nil,
          status: String.t() | nil,
          exit_code: integer() | nil,
          command_id: Ecto.UUID.t() | nil,
          node_id: Ecto.UUID.t() | nil,
          command_text: String.t() | nil,
          timeout: integer() | nil,
          completed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "command_executions" do
    field(:output, :string)
    field(:status, :string)
    field(:exit_code, :integer)
    field(:command_id, :binary_id)
    field(:node_id, :binary_id)
    field(:command_text, :string)
    field(:timeout, :integer)
    field(:completed_at, :utc_datetime)

    timestamps()
  end

  @doc false
  def changeset(command_execution, attrs) do
    command_execution
    |> cast(attrs, [
      :id,
      :command_id,
      :node_id,
      :command_text,
      :timeout,
      :status,
      :output,
      :exit_code,
      :completed_at
    ])
    |> validate_required([:id, :command_id, :node_id, :command_text, :status])
    |> validate_uuid_format(:id)
    |> validate_inclusion(:status, ["pending", "completed"])
    |> unique_constraint(:id, name: :command_executions_id_index)
  end

  defp validate_uuid_format(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case Ecto.UUID.cast(value) do
        {:ok, _} -> []
        :error -> [{field, "must be a valid UUID format"}]
      end
    end)
  end
end
