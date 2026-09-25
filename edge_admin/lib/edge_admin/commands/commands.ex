# edge_admin/lib/edge_admin/commands/commands.ex
defmodule EdgeAdmin.Commands do
  @moduledoc """
  The Commands context handles distributed command execution across edge nodes.

  A command is the requested shell text plus targeting. A command execution is
  the per-node row that moves through `pending -> sent` to a result status.
  `cancelled` and `expired` executions are finalized after Admin accepts an
  Agent result; `completed` and `dropped` are finalized immediately.

  ## Concurrency model

  This context runs on every admin in a multi-admin cluster simultaneously.
  Cluster ownership is eventually consistent and can flap during reconciliation;
  at any moment, two admins may both believe they own the same edge cluster.
  Independently, a single admin's HTTP round trip
  to an agent can outlast the agent's command execution, so the agent can
  report results back before the admin has finished marking the row `:sent`.

  Both situations were producing lost-update races on every status transition
  (a finalized row could be clobbered back to `:sent` or `:expired` by a stale
  in-memory struct). Every transition now uses a conditional database update
  that restricts the allowed source statuses and returns `{:error, :stale_state}`
  when a row has already moved. Early conflict checks remain useful, but the
  database is authoritative.

  Commands are globally visible, but delivery is local to the clusters currently
  owned by each Admin.
  """

  alias EdgeAdmin.Commands.Resources.CommandExecutionResources
  alias EdgeAdmin.Commands.Resources.CommandResources
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Commands.Workflows.CommandExecutionDelivery
  alias EdgeAdmin.Commands.Workflows.CommandExecutionLifecycle
  alias EdgeAdmin.Commands.Workflows.CommandExecutionRetention

  @spec get_command(String.t()) :: {:ok, Command.t()} | {:error, :not_found}
  defdelegate get_command(id), to: CommandResources, as: :get

  @doc "Lists commands with filtering, sorting, and pagination."
  @spec list_commands(map()) :: {:ok, {[Command.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_commands(params \\ %{}), to: CommandResources, as: :list

  @doc "Deletes a command after checking that all its executions are finalized."
  @spec delete_command(Command.t()) ::
          {:ok, Command.t()} | {:error, {:conflict, String.t()} | Ecto.Changeset.t()}
  defdelegate delete_command(command),
    to: CommandResources,
    as: :delete_if_all_executions_finalized

  @doc "Creates a command and atomically enqueues asynchronous execution creation."
  @spec create_command_and_enqueue_executions(map()) ::
          {:ok, Command.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_command_and_enqueue_executions(params), to: CommandExecutionDelivery

  @spec get_command_execution(String.t()) :: {:ok, CommandExecution.t()} | {:error, :not_found}
  defdelegate get_command_execution(id), to: CommandExecutionResources, as: :get

  @doc "Lists command executions with filtering, sorting, and pagination."
  @spec list_command_executions(map()) :: {:ok, {[CommandExecution.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_command_executions(params \\ %{}), to: CommandExecutionResources, as: :list

  @doc "Deletes a command execution after checking that it is finalized."
  @spec delete_command_execution(CommandExecution.t()) ::
          {:ok, CommandExecution.t()} | {:error, {:conflict, String.t()} | Ecto.Changeset.t()}
  defdelegate delete_command_execution(command_execution),
    to: CommandExecutionResources,
    as: :delete_if_finalized

  @spec create_command_executions(map()) :: {:ok, [CommandExecution.t()]} | {:error, String.t()}
  defdelegate create_command_executions(args), to: CommandExecutionDelivery

  @doc "Delivers pending executions for clusters owned by this Admin."
  @spec deliver_local_command_executions() :: :ok
  defdelegate deliver_local_command_executions(), to: CommandExecutionDelivery

  @type dropped_command_execution :: CommandExecutionLifecycle.dropped_command_execution()

  @doc "Marks pending or sent executions for a node as dropped."
  @spec drop_node_command_executions(String.t(), String.t()) :: [dropped_command_execution()]
  defdelegate drop_node_command_executions(node_id, cluster_name), to: CommandExecutionLifecycle

  @doc "Publishes events for executions dropped during node cleanup."
  @spec publish_dropped_command_executions([dropped_command_execution()]) :: :ok
  defdelegate publish_dropped_command_executions(dropped_command_executions), to: CommandExecutionLifecycle

  @doc "Acknowledges command execution receipt from an agent."
  @spec acknowledge_command_execution(CommandExecution.t()) ::
          {:ok, CommandExecution.t()}
          | {:error, {:conflict, String.t()}}
          | {:error, Ecto.Changeset.t()}
  defdelegate acknowledge_command_execution(execution), to: CommandExecutionLifecycle

  @doc "Updates a command execution with an agent-reported result."
  @spec update_command_execution_result(CommandExecution.t(), map()) ::
          {:ok, CommandExecution.t()}
          | {:error, {:conflict, String.t()}}
          | {:error, Ecto.Changeset.t()}
  defdelegate update_command_execution_result(execution, params), to: CommandExecutionLifecycle

  @doc "Cancels a command execution."
  @spec cancel_command_execution(CommandExecution.t()) ::
          {:ok, {:cancelled, CommandExecution.t()} | :accepted}
          | {:error, {:conflict, String.t()}}
          | {:error, :service_unavailable}
  defdelegate cancel_command_execution(execution), to: CommandExecutionLifecycle

  @doc "Expires stale command executions owned by this Admin."
  @spec expire_stale_command_executions() :: :ok
  defdelegate expire_stale_command_executions(), to: CommandExecutionRetention

  @doc "Deletes finalized command executions older than the retention period."
  @spec prune_command_executions(pos_integer()) :: {:ok, non_neg_integer()}
  defdelegate prune_command_executions(retention_days), to: CommandExecutionRetention
end
