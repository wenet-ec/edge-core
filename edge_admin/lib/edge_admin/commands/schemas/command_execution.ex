# edge_admin/lib/edge_admin/commands/schemas/command_execution.ex
defmodule EdgeAdmin.Commands.Schemas.CommandExecution do
  @moduledoc false
  use EdgeAdmin.Schema

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node

  # Lifecycle status registry. The schema's `Ecto.Enum` cast, the
  # `validate_inclusion`-equivalent enforcement, the public predicate
  # functions, and external surfaces (controller / MCP / AsyncAPI enums)
  # all derive from these lists — single source of truth.
  @statuses [:pending, :sent, :completed, :cancelled, :expired]
  @terminal_statuses [:completed, :cancelled, :expired]
  @cancellable_statuses [:pending, :sent]

  @type status :: :pending | :sent | :completed | :cancelled | :expired

  @type t :: %__MODULE__{
          id: String.t(),
          output: String.t() | nil,
          status: status(),
          exit_code: integer() | nil,
          target_all: boolean(),
          sent_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          cancelled_at: DateTime.t() | nil,
          command_text: String.t() | nil,
          timeout: integer() | nil,
          cluster_name: String.t() | nil,
          expired_at: DateTime.t() | nil,
          command_id: String.t() | nil,
          command: Command.t() | NotLoaded.t() | nil,
          node_id: String.t(),
          node: Node.t() | NotLoaded.t(),
          cluster_id: String.t() | nil,
          cluster: Cluster.t() | NotLoaded.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
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
    # "output" will be mapped to TEXT in database
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
    field(:expired_at, :utc_datetime, virtual: true)

    # Associations
    belongs_to(:command, Command)
    belongs_to(:node, Node)
    belongs_to(:cluster, Cluster)

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

  @doc """
  Returns the expiration deadline for this execution.
  Derived from the command's expired_at — this is the deadline, not the event timestamp.
  Requires command association to be preloaded.
  Returns nil if no expiration is set.
  """
  def expired_at(%__MODULE__{command: %{expired_at: expired_at}}), do: expired_at
  def expired_at(%__MODULE__{}), do: nil

  # ---------------------------------------------------------------------------
  # Status registry
  # ---------------------------------------------------------------------------

  @doc "All lifecycle statuses, in canonical order."
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc "Statuses that represent a finished execution (no further transitions)."
  @spec terminal_statuses() :: [status()]
  def terminal_statuses, do: @terminal_statuses

  @doc "Statuses from which a cancellation request is accepted."
  @spec cancellable_statuses() :: [status()]
  def cancellable_statuses, do: @cancellable_statuses

  @doc "Wire-format strings (sorted to match `statuses/0`). For OpenAPI / MCP enums."
  @spec status_strings() :: [String.t()]
  def status_strings, do: Enum.map(@statuses, &Atom.to_string/1)

  @doc "True when the execution is in a terminal status."
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{status: status}), do: status in @terminal_statuses

  @doc "True when the execution can still be cancelled."
  @spec cancellable?(t()) :: boolean()
  def cancellable?(%__MODULE__{status: status}), do: status in @cancellable_statuses
end
