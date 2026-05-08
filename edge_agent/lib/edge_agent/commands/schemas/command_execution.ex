# edge_agent/lib/edge_agent/commands/schemas/command_execution.ex
defmodule EdgeAgent.Commands.Schemas.CommandExecution do
  @moduledoc false
  use EdgeAgent.Schema

  # Lifecycle status registry. The agent only sees three states locally
  # (`:sent` and `:cancelled` are admin-only). The schema's `Ecto.Enum`
  # cast and external surfaces (form / wire serialization) all derive
  # from this list — single source of truth.
  @statuses [:pending, :completed, :expired]

  @type status :: :pending | :completed | :expired

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          output: String.t() | nil,
          status: status() | nil,
          exit_code: integer() | nil,
          command_id: Ecto.UUID.t() | nil,
          node_id: Ecto.UUID.t() | nil,
          command_text: String.t() | nil,
          timeout: integer() | nil,
          expired_at: DateTime.t() | nil,
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
    field(:expired_at, :utc_datetime)
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
      :expired_at,
      :status,
      :output,
      :exit_code,
      :completed_at
    ])
    |> validate_required([:id, :command_id, :node_id, :command_text, :status])
    |> unique_constraint(:id, name: :command_executions_id_index)
  end

  # ---------------------------------------------------------------------------
  # Status registry
  # ---------------------------------------------------------------------------

  @doc "All locally-tracked statuses, in canonical order."
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc "Wire-format strings for OpenAPI / form / sync surfaces."
  @spec status_strings() :: [String.t()]
  def status_strings, do: Enum.map(@statuses, &Atom.to_string/1)
end
