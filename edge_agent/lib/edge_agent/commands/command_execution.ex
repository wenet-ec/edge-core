# edge_agent/lib/edge_agent/commands/command_execution.ex
defmodule EdgeAgent.Commands.CommandExecution do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "command_executions" do
    field :output, :string
    field :status, :string
    field :exit_code, :integer
    field :command_id, :binary_id
    field :node_id, :binary_id
    field :command_text, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(command_execution, attrs) do
    command_execution
    |> cast(attrs, [:command_id, :node_id, :command_text, :status, :output, :exit_code])
    |> validate_required([:command_id, :node_id, :command_text, :status])
    |> validate_inclusion(:status, ["pending", "completed"])
  end
end
