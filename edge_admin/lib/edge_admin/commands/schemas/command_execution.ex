# edge_admin/lib/edge_admin/commands/schemas/command_execution.ex
defmodule EdgeAdmin.Commands.Schemas.CommandExecution do
  @moduledoc false
  use EdgeAdmin.Schema

  @type t :: %__MODULE__{}

  @derive {
    Flop.Schema,
    filterable: [:status, :target_all, :exit_code, :command_id, :node_id, :output, :inserted_at],
    sortable: [:status, :exit_code, :sent_at, :completed_at, :inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  schema "command_executions" do
    # "output" will be mapped to TEXT in database
    field(:output, :string)
    field(:status, :string)
    field(:exit_code, :integer)
    field(:target_all, :boolean, default: false)
    field(:sent_at, :utc_datetime)
    field(:completed_at, :utc_datetime)

    field(:command_text, :string, virtual: true)
    field(:timeout, :integer, virtual: true)
    field(:cluster_name, :string, virtual: true)

    # Associations
    belongs_to(:command, EdgeAdmin.Commands.Schemas.Command)
    belongs_to(:node, EdgeAdmin.Nodes.Schemas.Node)
    belongs_to(:cluster, EdgeAdmin.Nodes.Schemas.Cluster)

    timestamps()
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
      :cluster_id
    ])
    |> validate_required([:status, :node_id])
    |> validate_inclusion(:status, ["pending", "sent", "completed"])
    |> foreign_key_constraint(:command_id)
    |> foreign_key_constraint(:node_id)
    |> foreign_key_constraint(:cluster_id)
    |> unique_constraint([:node_id, :command_id],
      name: :command_executions_node_id_command_id_index
    )
  end

  @doc """
  Returns the command text for this execution.
  Requires command association to be preloaded.
  """
  def command_text(%__MODULE__{command: %{command_text: command_text}}), do: command_text
  def command_text(%__MODULE__{}), do: nil

  @doc """
  Returns the cluster name for this execution.
  Requires cluster association to be preloaded.
  Returns nil if no cluster is associated.
  """
  def cluster_name(%__MODULE__{cluster: %{name: name}}), do: name
  def cluster_name(%__MODULE__{}), do: nil

  @doc """
  Returns the timeout for this execution in milliseconds.
  Requires command association to be preloaded.
  Returns nil if no timeout is set.
  """
  def timeout(%__MODULE__{command: %{timeout: timeout}}), do: timeout
  def timeout(%__MODULE__{}), do: nil
end
