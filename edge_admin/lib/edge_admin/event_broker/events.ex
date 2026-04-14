# edge_admin/lib/edge_admin/event_broker/events.ex
defmodule EdgeAdmin.EventBroker.Events do
  @moduledoc """
  Typed event structs for all 13 broker events.

  Each struct carries the raw domain data needed to build the event envelope's
  `data` field. Callers construct the appropriate struct and pass it to
  `EventBroker.publish/1`.

  ## Node events

      %Events.NodeRegistered{node: node}
      %Events.NodeReregistered{node: node}
      %Events.NodeVersionChanged{node: node, previous_version: "1.1.0"}
      %Events.NodeStatusChanged{node: node, previous_status: "healthy"}
      %Events.NodeClusterChanged{node: node, previous_cluster_name: "old"}
      %Events.NodeUpdateTriggered{node: node, self_update_request_id: id}
      %Events.NodeDeleted{node: node}

  ## Execution events

      %Events.ExecutionCreated{execution: execution, command: command, cluster_name: "prod"}
      %Events.ExecutionSent{execution: execution, command: command, cluster_name: "prod"}
      %Events.ExecutionCompleted{execution: execution, command: command, cluster_name: "prod"}
      %Events.ExecutionCancelled{execution: execution, command: command, cluster_name: "prod"}
      %Events.ExecutionExpired{execution: execution, command: command, cluster_name: "prod"}

  ## Self-update events

      %Events.SelfUpdateCreated{request: request}
      %Events.SelfUpdateCompleted{request: request}
  """

  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest

  # ---------------------------------------------------------------------------
  # Node event structs
  # ---------------------------------------------------------------------------

  defmodule NodeRegistered do
    @moduledoc false
    @enforce_keys [:node]
    defstruct [:node]
    @type t :: %__MODULE__{node: Node.t()}
  end

  defmodule NodeReregistered do
    @moduledoc false
    @enforce_keys [:node]
    defstruct [:node]
    @type t :: %__MODULE__{node: Node.t()}
  end

  defmodule NodeVersionChanged do
    @moduledoc false
    @enforce_keys [:node, :previous_version]
    defstruct [:node, :previous_version]
    @type t :: %__MODULE__{node: Node.t(), previous_version: String.t() | nil}
  end

  defmodule NodeStatusChanged do
    @moduledoc false
    @enforce_keys [:node, :previous_status]
    defstruct [:node, :previous_status]
    @type t :: %__MODULE__{node: Node.t(), previous_status: String.t()}
  end

  defmodule NodeClusterChanged do
    @moduledoc false
    @enforce_keys [:node, :previous_cluster_name]
    defstruct [:node, :previous_cluster_name]
    @type t :: %__MODULE__{node: Node.t(), previous_cluster_name: String.t()}
  end

  defmodule NodeUpdateTriggered do
    @moduledoc false
    @enforce_keys [:node, :self_update_request_id]
    defstruct [:node, :self_update_request_id]
    @type t :: %__MODULE__{node: Node.t(), self_update_request_id: String.t()}
  end

  defmodule NodeDeleted do
    @moduledoc false
    @enforce_keys [:node]
    defstruct [:node]
    @type t :: %__MODULE__{node: Node.t()}
  end

  # ---------------------------------------------------------------------------
  # Execution event structs
  # ---------------------------------------------------------------------------

  defmodule ExecutionCreated do
    @moduledoc false
    @enforce_keys [:execution, :command, :cluster_name]
    defstruct [:execution, :command, :cluster_name]

    @type t :: %__MODULE__{
            execution: CommandExecution.t(),
            command: Command.t(),
            cluster_name: String.t()
          }
  end

  defmodule ExecutionSent do
    @moduledoc false
    @enforce_keys [:execution, :command, :cluster_name]
    defstruct [:execution, :command, :cluster_name]

    @type t :: %__MODULE__{
            execution: CommandExecution.t(),
            command: Command.t(),
            cluster_name: String.t()
          }
  end

  defmodule ExecutionCompleted do
    @moduledoc false
    @enforce_keys [:execution, :command, :cluster_name]
    defstruct [:execution, :command, :cluster_name]

    @type t :: %__MODULE__{
            execution: CommandExecution.t(),
            command: Command.t(),
            cluster_name: String.t()
          }
  end

  defmodule ExecutionCancelled do
    @moduledoc false
    @enforce_keys [:execution, :command, :cluster_name]
    defstruct [:execution, :command, :cluster_name]

    @type t :: %__MODULE__{
            execution: CommandExecution.t(),
            command: Command.t(),
            cluster_name: String.t()
          }
  end

  defmodule ExecutionExpired do
    @moduledoc false
    @enforce_keys [:execution, :command, :cluster_name]
    defstruct [:execution, :command, :cluster_name]

    @type t :: %__MODULE__{
            execution: CommandExecution.t(),
            command: Command.t(),
            cluster_name: String.t()
          }
  end

  # ---------------------------------------------------------------------------
  # Self-update event structs
  # ---------------------------------------------------------------------------

  defmodule SelfUpdateCreated do
    @moduledoc false
    @enforce_keys [:request]
    defstruct [:request]
    @type t :: %__MODULE__{request: SelfUpdateRequest.t()}
  end

  defmodule SelfUpdateCompleted do
    @moduledoc false
    @enforce_keys [:request]
    defstruct [:request]
    @type t :: %__MODULE__{request: SelfUpdateRequest.t()}
  end

  # ---------------------------------------------------------------------------
  # Protocol: event_type/1 and to_data/1
  # ---------------------------------------------------------------------------

  @doc "Returns the string event type for the given event struct."
  @spec event_type(term()) :: String.t()
  def event_type(%NodeRegistered{}), do: "edge.node.registered"
  def event_type(%NodeReregistered{}), do: "edge.node.reregistered"
  def event_type(%NodeVersionChanged{}), do: "edge.node.version_changed"
  def event_type(%NodeStatusChanged{}), do: "edge.node.status_changed"
  def event_type(%NodeClusterChanged{}), do: "edge.node.cluster_changed"
  def event_type(%NodeUpdateTriggered{}), do: "edge.node.update_triggered"
  def event_type(%NodeDeleted{}), do: "edge.node.deleted"
  def event_type(%ExecutionCreated{}), do: "edge.execution.created"
  def event_type(%ExecutionSent{}), do: "edge.execution.sent"
  def event_type(%ExecutionCompleted{}), do: "edge.execution.completed"
  def event_type(%ExecutionCancelled{}), do: "edge.execution.cancelled"
  def event_type(%ExecutionExpired{}), do: "edge.execution.expired"
  def event_type(%SelfUpdateCreated{}), do: "edge.self_update.created"
  def event_type(%SelfUpdateCompleted{}), do: "edge.self_update.completed"

  @doc "Builds the `data` map for the event envelope."
  @spec to_data(term()) :: map()

  # Node events — base snapshot, then overlay any extra fields
  def to_data(%NodeRegistered{node: node}), do: node_data(node)
  def to_data(%NodeReregistered{node: node}), do: node_data(node)

  def to_data(%NodeVersionChanged{node: node, previous_version: prev}) do
    node |> node_data() |> Map.put("previous_version", prev)
  end

  def to_data(%NodeStatusChanged{node: node, previous_status: prev}) do
    node |> node_data() |> Map.put("previous_status", prev)
  end

  def to_data(%NodeClusterChanged{node: node, previous_cluster_name: prev}) do
    node |> node_data() |> Map.put("previous_cluster_name", prev)
  end

  def to_data(%NodeUpdateTriggered{node: node, self_update_request_id: req_id}) do
    node |> node_data() |> Map.put("self_update_request_id", req_id)
  end

  def to_data(%NodeDeleted{node: node}), do: node_data(node)

  # Execution events — base snapshot (output excluded)
  def to_data(%ExecutionCreated{execution: ex, command: cmd, cluster_name: cn}), do: execution_data(ex, cmd, cn)

  def to_data(%ExecutionSent{execution: ex, command: cmd, cluster_name: cn}), do: execution_data(ex, cmd, cn)

  def to_data(%ExecutionCompleted{execution: ex, command: cmd, cluster_name: cn}), do: execution_data(ex, cmd, cn)

  def to_data(%ExecutionCancelled{execution: ex, command: cmd, cluster_name: cn}), do: execution_data(ex, cmd, cn)

  def to_data(%ExecutionExpired{execution: ex, command: cmd, cluster_name: cn}), do: execution_data(ex, cmd, cn)

  # Self-update events
  def to_data(%SelfUpdateCreated{request: req}), do: self_update_data(req)
  def to_data(%SelfUpdateCompleted{request: req}), do: self_update_data(req)

  # ---------------------------------------------------------------------------
  # Data builders — full object snapshots, no internal/secret fields
  # ---------------------------------------------------------------------------

  defp node_data(node) do
    %{
      "node_id" => node.id,
      "cluster_name" => cluster_name(node),
      "status" => node.status,
      "version" => node.version,
      "id_type" => node.id_type,
      "http_port" => node.http_port,
      "ssh_port" => node.ssh_port,
      "host_metrics_port" => node.host_metrics_port,
      "wireguard_metrics_port" => node.wireguard_metrics_port,
      "http_proxy_port" => node.http_proxy_port,
      "socks5_proxy_port" => node.socks5_proxy_port,
      "self_update_enabled" => node.self_update_enabled,
      "last_seen_at" => format_dt(node.last_seen_at),
      "inserted_at" => format_dt(node.inserted_at),
      "updated_at" => format_dt(node.updated_at)
    }
  end

  defp execution_data(execution, command, cluster_name) do
    %{
      "execution_id" => execution.id,
      "command_id" => execution.command_id,
      "node_id" => execution.node_id,
      "cluster_name" => cluster_name,
      "command_text" => command.command_text,
      "timeout" => command.timeout,
      "status" => execution.status,
      "exit_code" => execution.exit_code,
      "target_all" => execution.target_all,
      "expired_at" => format_dt(command.expired_at),
      "sent_at" => format_dt(execution.sent_at),
      "completed_at" => format_dt(execution.completed_at),
      "cancelled_at" => format_dt(execution.cancelled_at),
      "inserted_at" => format_dt(execution.inserted_at),
      "updated_at" => format_dt(execution.updated_at)
    }
  end

  defp self_update_data(request) do
    %{
      "request_id" => request.id,
      "status" => request.status,
      "targeting" => request.targeting,
      "summary" => request.summary,
      "inserted_at" => format_dt(request.inserted_at),
      "updated_at" => format_dt(request.updated_at)
    }
  end

  defp cluster_name(%{cluster: %{name: name}}), do: name
  defp cluster_name(_), do: nil

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt) <> "Z"
end
