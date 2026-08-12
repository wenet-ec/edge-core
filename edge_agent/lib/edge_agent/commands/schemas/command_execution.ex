# edge_agent/lib/edge_agent/commands/schemas/command_execution.ex
defmodule EdgeAgent.Commands.Schemas.CommandExecution do
  @moduledoc "Ecto schema for a command execution tracked locally by the Agent."
  use EdgeAgent.Schema

  # Lifecycle status registry. The agent only sees four states locally
  # (`:sent` and `:cancelled` are admin-only). The schema's `Ecto.Enum`
  # cast derives from this list. The incoming Admin form deliberately accepts
  # only `:pending`; `:running` is Agent-internal lifecycle state.
  @statuses [:pending, :running, :completed, :expired]

  @type status :: :pending | :running | :completed | :expired

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
      if timeout > 0 do
        []
      else
        [timeout: "must be a positive number (in milliseconds)"]
      end
    end)
  end

  @doc "All locally-tracked statuses, in canonical order."
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc "Wire-format strings for OpenAPI / form / sync surfaces."
  @spec status_strings() :: [String.t()]
  def status_strings, do: Enum.map(@statuses, &Atom.to_string/1)
end
