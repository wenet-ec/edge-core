# edge_agent/lib/edge_agent/commands/schemas/command_execution.ex
defmodule EdgeAgent.Commands.Schemas.CommandExecution do
  @moduledoc "Ecto schema for a command execution tracked locally by the Agent."
  use EdgeAgent.Schema

  alias EdgeAgent.Commands.Enums.CommandExecutionStatuses
  alias EdgeAgent.Commands.Validators.CommandExecutionValidators

  @statuses CommandExecutionStatuses.statuses()

  @type status :: CommandExecutionStatuses.t()

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          output: String.t() | nil,
          status: status() | nil,
          exit_code: integer() | nil,
          command_id: Ecto.UUID.t() | nil,
          node_id: Ecto.UUID.t() | nil,
          command_text: String.t() | nil,
          timeout: integer() | nil,
          expires_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "command_executions" do
    field(:output, :string)
    field(:status, Ecto.Enum, values: @statuses)
    field(:exit_code, :integer)
    field(:command_id, :binary_id)
    field(:node_id, :binary_id)
    field(:command_text, :string)
    field(:timeout, :integer)
    field(:expires_at, :utc_datetime)
    field(:completed_at, :utc_datetime)

    timestamps()
  end

  @doc "Builds a changeset for creating or updating a local command execution."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(command_execution, attrs) do
    command_execution
    |> cast(attrs, [
      :id,
      :command_id,
      :node_id,
      :command_text,
      :timeout,
      :expires_at,
      :status,
      :output,
      :exit_code,
      :completed_at
    ])
    |> validate_required([:id, :command_id, :node_id, :command_text, :status])
    |> check_constraint(:command_text, name: :command_executions_command_text_present)
    |> validate_timeout()
    |> check_constraint(:timeout, name: :command_executions_timeout_positive)
    |> unique_constraint(:id, name: :command_executions_id_index)
  end

  defp validate_timeout(changeset) do
    validate_change(changeset, :timeout, fn :timeout, timeout ->
      if CommandExecutionValidators.valid_timeout?(timeout) do
        []
      else
        [timeout: CommandExecutionValidators.timeout_error()]
      end
    end)
  end
end
