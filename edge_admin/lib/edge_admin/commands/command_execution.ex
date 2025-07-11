# edge_admin/lib/edge_admin/commands/command_execution.ex
defmodule EdgeAdmin.Commands.CommandExecution do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "command_executions" do
    # Maps to TEXT in database
    field(:output, :string)
    field(:status, :string)
    field(:exit_code, :integer)
    field(:target_all, :boolean, default: false)
    field(:sent_at, :utc_datetime)
    field(:completed_at, :utc_datetime)

    # Virtual field for cleaner access to command text
    field(:command_text, :string, virtual: true)

    # Associations
    belongs_to(:command, EdgeAdmin.Commands.Command)
    belongs_to(:node, EdgeAdmin.Nodes.Node)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(command_execution, attrs) do
    command_execution
    |> cast(attrs, [
      :status,
      :target_all,
      :output,
      :exit_code,
      :sent_at,
      :completed_at,
      :command_id,
      :node_id,
      # Include virtual field in cast
      :command_text
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, ["pending", "sent", "completed"])
    |> validate_node_or_target_all()
    |> foreign_key_constraint(:command_id)
    |> foreign_key_constraint(:node_id)
    |> unique_constraint([:node_id, :command_id],
      name: :command_executions_node_id_command_id_index
    )
  end

  def populate_command_text(%__MODULE__{command: %{command_text: command_text}} = execution) do
    %{execution | command_text: command_text}
  end

  def populate_command_text(%__MODULE__{} = execution) do
    %{execution | command_text: nil}
  end

  @doc false
  defp validate_node_or_target_all(changeset) do
    target_all = get_field(changeset, :target_all)
    node_id = get_field(changeset, :node_id)

    cond do
      target_all == true ->
        changeset

      target_all == false and is_nil(node_id) ->
        add_error(changeset, :node_id, "must be present when target_all is false")

      true ->
        changeset
    end
  end
end
