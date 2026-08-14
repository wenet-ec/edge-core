# edge_admin/lib/edge_admin/commands/schemas/command_execution.ex
defmodule EdgeAdmin.Commands.Schemas.CommandExecution do
  @moduledoc "Ecto schema for one node's execution of a command."
  use EdgeAdmin.Schema

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.Commands.Enums.CommandExecutionStatuses
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node

  @statuses CommandExecutionStatuses.statuses()
  @terminal_statuses CommandExecutionStatuses.terminal_statuses()
  @cancellable_statuses CommandExecutionStatuses.cancellable_statuses()

  @type status :: CommandExecutionStatuses.t()

  @type t :: %__MODULE__{
          id: String.t() | nil,
          output: String.t() | nil,
          status: status() | nil,
          exit_code: integer() | nil,
          target_all: boolean() | nil,
          sent_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          cancelled_at: DateTime.t() | nil,
          command_text: String.t() | nil,
          timeout: integer() | nil,
          cluster_name: String.t() | nil,
          expires_at: DateTime.t() | nil,
          command_id: String.t() | nil,
          command: Command.t() | NotLoaded.t() | nil,
          node_id: String.t() | nil,
          node: Node.t() | NotLoaded.t() | nil,
          cluster_id: String.t() | nil,
          cluster: Cluster.t() | NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @derive {
    Flop.Schema,
    filterable: [
      :status,
      :target_all,
      :exit_code,
      :command_id,
      :node_id,
      :output,
      :inserted_at,
      :updated_at,
      :sent_at,
      :completed_at,
      :cancelled_at
    ],
    sortable: [:status, :exit_code, :sent_at, :completed_at, :cancelled_at, :inserted_at, :updated_at],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  schema "command_executions" do
    field(:output, :string)
    field(:status, Ecto.Enum, values: @statuses)
    field(:exit_code, :integer)
    field(:target_all, :boolean, default: false)
    field(:sent_at, :utc_datetime)
    field(:completed_at, :utc_datetime)
    field(:cancelled_at, :utc_datetime)

    field(:command_text, :string, virtual: true)
    field(:timeout, :integer, virtual: true)
    field(:cluster_name, :string, virtual: true)
    field(:expires_at, :utc_datetime, virtual: true)

    belongs_to(:command, Command)
    belongs_to(:node, Node)
    belongs_to(:cluster, Cluster)

    timestamps()
  end

  @doc "Builds a changeset for creating or updating a command execution."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(command_execution, attrs) do
    command_execution
    |> cast(attrs, [
      :status,
      :target_all,
      :output,
      :exit_code,
      :sent_at,
      :completed_at,
      :cancelled_at,
      :command_id,
      :node_id,
      :cluster_id
    ])
    |> validate_required([:status, :node_id])
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
  @spec command_text(t()) :: String.t() | nil
  def command_text(%__MODULE__{command: %{command_text: command_text}}), do: command_text
  def command_text(%__MODULE__{}), do: nil

  @doc """
  Returns the cluster name for this execution.
  Requires cluster association to be preloaded.
  Returns nil if no cluster is associated.
  """
  @spec cluster_name(t()) :: String.t() | nil
  def cluster_name(%__MODULE__{cluster: %{name: name}}), do: name
  def cluster_name(%__MODULE__{}), do: nil

  @doc """
  Returns the timeout for this execution in milliseconds.
  Requires command association to be preloaded.
  Returns nil if no timeout is set.
  """
  @spec timeout(t()) :: integer() | nil
  def timeout(%__MODULE__{command: %{timeout: timeout}}), do: timeout
  def timeout(%__MODULE__{}), do: nil

  @doc """
  Returns the expiration deadline for this execution.
  Derived from the command's expires_at — this is the deadline, not the event timestamp.
  Requires command association to be preloaded.
  Returns nil if no expiration is set.
  """
  @spec expires_at(t()) :: DateTime.t() | nil
  def expires_at(%__MODULE__{command: %{expires_at: expires_at}}), do: expires_at
  def expires_at(%__MODULE__{}), do: nil

  @doc "True when the execution is in a terminal status."
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{status: status}), do: status in @terminal_statuses

  @doc "True when the execution can still be cancelled."
  @spec cancellable?(t()) :: boolean()
  def cancellable?(%__MODULE__{status: status}), do: status in @cancellable_statuses
end
