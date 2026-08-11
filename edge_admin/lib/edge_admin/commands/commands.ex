# edge_admin/lib/edge_admin/commands/commands.ex
defmodule EdgeAdmin.Commands do
  @moduledoc """
  The Commands context handles distributed command execution across edge nodes.

  This module provides the core functionality for creating commands, managing their
  execution lifecycle, and delivering them to target nodes. Commands are executed
  asynchronously with status tracking.

  ## Key Concepts

  - **Command**: A shell command to be executed (e.g., `"uptime"`, `"systemctl restart nginx"`)
  - **Command Execution**: A single instance of a command targeted at a specific node
  - **Targeting**: Specification of which nodes should execute a command (all/specific nodes/clusters)
  - **Delivery**: Process of sending pending executions to healthy nodes via HTTP
  - **Status Lifecycle**: `pending` → `sent` → `completed`
    - Terminal states: `completed` | `cancelled` | `expired` | `dropped`
    - From `pending` or `sent`: admin can cancel; scheduler can mark `expired`
      when the command's `expires_at` passes
    - Race-window detail: `cancelled` / `expired` rows with `nil exit_code`
      can still be overwritten by a late agent report
      (see `Checks.CommandExecutionAcceptsResultCheck`)

  ## Concurrency model

  This context runs on every admin in a multi-admin cluster simultaneously.
  Cluster ownership (via `Admins.Metadata`) is *eventually* consistent and can
  flap during reconciliation — at any moment, two admins may both believe they
  own the same edge cluster. Independently, a single admin's HTTP round trip
  to an agent can outlast the agent's command execution, so the agent can
  report results back before the admin has finished marking the row `:sent`.

  Both situations were producing lost-update races on every status transition
  (a terminal row could be clobbered back to `:sent` or `:expired` by a stale
  in-memory struct). Every transition now flows through `transition_status/3`
  or `transition_to_result/2`, which run a single conditional `UPDATE … WHERE
  status IN (allowed)` and return `{:error, :stale_state}` if the row already
  left the expected source status. Check modules (`Checks.Execution*`) remain
  as early 409 gates but the DB is authoritative.

  ## Architecture

  ### Async Execution Flow
  1. Command created with targeting specification
  2. Background worker creates execution records for targeted nodes
  3. Scheduler delivers pending executions to healthy nodes (every minute,
     `EXECUTION_DELIVERY_SCHEDULE`, default `* * * * *`)
  4. Nodes execute commands and report results back
  5. Executions marked as completed with output and exit code

  ### Distributed Ownership
  - Commands are globally visible (all admins can see them)
  - Execution delivery is distributed (each admin delivers to its owned clusters)
  - Uses Metadata ETS to determine cluster ownership

  ## Examples

      # Create a command for all nodes
      iex> create_command_and_executions(%{
      ...>   "command_text" => "uptime",
      ...>   "targeting" => %{"type" => "all"}
      ...> })
      {:ok, %Command{}}

      # Create a command for specific nodes
      iex> create_command_and_executions(%{
      ...>   "command_text" => "systemctl restart nginx",
      ...>   "targeting" => %{"type" => "nodes", "node_ids" => ["abc-123", "def-456"]}
      ...> })
      {:ok, %Command{}}

      # List executions for a command
      iex> list_command_executions(%{"command_id" => command.id})
      {:ok, {[%CommandExecution{}, ...], %Flop.Meta{}}}

      # Cancel a pending execution
      iex> cancel_command_execution(execution)
      {:ok, {:cancelled, %CommandExecution{}}}
  """

  alias EdgeAdmin.Commands.Resources.CommandExecutions, as: CommandExecutionResource
  alias EdgeAdmin.Commands.Resources.Commands, as: CommandResource
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Commands.Workflows.CommandExecutionLifecycle
  alias EdgeAdmin.Commands.Workflows.Delivery
  alias EdgeAdmin.Commands.Workflows.Retention

  @doc """
  Gets a single command by ID.

  ## Parameters
  - `id` - The command's UUID

  ## Returns
  - `{:ok, command}` - Command found
  - `{:error, :not_found}` - Command doesn't exist or invalid UUID

  ## Examples

      iex> get_command(command_id)
      {:ok, %Command{command_text: "uptime"}}
  """
  @spec get_command(String.t()) :: {:ok, Command.t()} | {:error, :not_found}
  defdelegate get_command(id), to: CommandResource, as: :get

  @doc """
  Creates a new command.

  ## Parameters
  - `attrs` - Map of command attributes

  ## Returns
  - `{:ok, command}` - Command created successfully
  - `{:error, changeset}` - Validation failed
  """
  @spec create_command(map()) :: {:ok, Command.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_command(attrs \\ %{}), to: CommandResource, as: :create

  @doc """
  Updates a command.

  ## Parameters
  - `command` - The command struct to update
  - `attrs` - Map of attributes to update

  ## Returns
  - `{:ok, command}` - Update succeeded
  - `{:error, changeset}` - Validation failed
  """
  @spec update_command(Command.t(), map()) :: {:ok, Command.t()} | {:error, Ecto.Changeset.t()}
  defdelegate update_command(command, attrs), to: CommandResource, as: :update

  @doc """
  Deletes a command.

  Validates that command has no associated executions before deletion.

  ## Parameters
  - `command` - The command struct to delete

  ## Returns
  - `{:ok, command}` - Deletion succeeded
  - `{:error, {:conflict, reason}}` - Command has non-terminal executions
  """
  @spec delete_command(Command.t()) :: {:ok, Command.t()} | {:error, {:conflict, String.t()}}
  defdelegate delete_command(command), to: CommandResource, as: :delete

  @doc """
  Returns a changeset for tracking command changes (for forms).

  ## Examples

      iex> change_command(command)
      %Ecto.Changeset{data: %Command{}}
  """
  @spec change_command(Command.t(), map()) :: Ecto.Changeset.t()
  defdelegate change_command(command, attrs \\ %{}), to: CommandResource, as: :change

  @doc """
  Lists commands with filtering, sorting, and pagination.

  Supports filtering by:
  - `command_text` - Text search with wildcard support
  - `timeout` - Exact, `__gte`, `__lte` (milliseconds; null = no timeout)
  - `has_timeout` - Boolean: true returns commands with a timeout set
  - `expires_at__gte/lte` - Date range filter
  - `has_expires_at` - Boolean: true returns commands with an expiry set
  - `inserted_at__gte/lte` - Date range filter
  - `updated_at__gte/lte` - Date range filter

  ## Returns
  - `{:ok, {commands, meta}}` - List of commands with Flop.Meta pagination info
  - `{:error, meta}` - Validation errors (when replace_invalid_params: false)
  """
  @spec list_commands(map()) :: {:ok, {[Command.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_commands(params \\ %{}), to: CommandResource, as: :list

  @doc """
  Gets a single command execution by ID.

  ## Parameters
  - `id` - The execution's UUID

  ## Returns
  - `{:ok, execution}` - Execution found (with command preloaded)
  - `{:error, :not_found}` - Execution doesn't exist or invalid UUID
  """
  @spec get_command_execution(String.t()) :: {:ok, CommandExecution.t()} | {:error, :not_found}
  defdelegate get_command_execution(id), to: CommandExecutionResource, as: :get

  @doc """
  Creates a new command execution.

  ## Parameters
  - `attrs` - Map of execution attributes

  ## Returns
  - `{:ok, execution}` - Execution created successfully
  - `{:error, changeset}` - Validation failed
  """
  @spec create_command_execution(map()) :: {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_command_execution(attrs \\ %{}), to: CommandExecutionResource, as: :create

  @doc """
  Updates a command execution.

  ## Parameters
  - `command_execution` - The execution struct to update
  - `attrs` - Map of attributes to update

  ## Returns
  - `{:ok, execution}` - Update succeeded
  - `{:error, changeset}` - Validation failed
  """
  @spec update_command_execution(CommandExecution.t(), map()) ::
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()}
  defdelegate update_command_execution(command_execution, attrs), to: CommandExecutionResource, as: :update

  @doc """
  Deletes a command execution.

  Validates that execution is in a deletable state.

  ## Parameters
  - `command_execution` - The execution struct to delete

  ## Returns
  - `{:ok, execution}` - Deletion succeeded
  - `{:error, {:conflict, reason}}` - Execution is not completed
  """
  @spec delete_command_execution(CommandExecution.t()) ::
          {:ok, CommandExecution.t()} | {:error, {:conflict, String.t()}}
  defdelegate delete_command_execution(command_execution), to: CommandExecutionResource, as: :delete

  @doc """
  Returns a changeset for tracking execution changes (for forms).

  ## Examples

      iex> change_command_execution(execution)
      %Ecto.Changeset{data: %CommandExecution{}}
  """
  @spec change_command_execution(CommandExecution.t(), map()) :: Ecto.Changeset.t()
  defdelegate change_command_execution(command_execution, attrs \\ %{}), to: CommandExecutionResource, as: :change

  @doc """
  Lists command executions with filtering, sorting, and pagination.

  Supports filtering by:
  - `status__in` - Enum IN: `"pending"`, `"sent"`, `"completed"`, `"cancelled"`, `"expired"`, `"dropped"` — comma-separated list (`status__in=pending,sent`)
  - `target_all` - Boolean
  - `exit_code` - Exact, `__gte`, `__lte`
  - `command_id__in` - Exact IN match on command IDs — comma-separated UUIDs
  - `node_id__in` - Exact IN match on node IDs — comma-separated UUIDs
  - `output` - Text search with wildcard support
  - `cluster_name` - Wildcard (`prod*`), exact, or comma-separated IN match on cluster name (via node's cluster)
  - `has_cluster` - Boolean (filters by cluster_id presence: true = NOT NULL, false = IS NULL)
  - `has_output` - Boolean: true returns executions with output present
  - `inserted_at__gte/lte` - Date range filter
  - `updated_at__gte/lte` - Date range filter
  - `sent_at__gte/lte` - Date range filter
  - `completed_at__gte/lte` - Date range filter
  - `cancelled_at__gte/lte` - Date range filter

  ## Returns
  - `{:ok, {command_executions, meta}}` - List of command executions with Flop.Meta pagination info
  - `{:error, meta}` - Validation errors (when replace_invalid_params: false)
  """
  @spec list_command_executions(map()) :: {:ok, {[CommandExecution.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_command_executions(params \\ %{}), to: CommandExecutionResource, as: :list

  @doc "Creates a command and enqueues execution creation."
  @spec create_command_and_executions(map()) :: {:ok, Command.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_command_and_executions(params), to: Delivery

  @doc "Creates command executions from targeting arguments."
  @spec create_command_executions(map()) :: {:ok, [CommandExecution.t()]} | {:error, String.t()}
  defdelegate create_command_executions(args), to: Delivery

  @doc "Delivers pending executions for clusters owned by this Admin."
  @spec deliver_local_command_executions() :: :ok
  defdelegate deliver_local_command_executions(), to: Delivery

  @type dropped_command_execution :: CommandExecutionLifecycle.dropped_command_execution()

  @doc "Marks pending or sent executions for a node as dropped."
  @spec drop_node_command_executions(String.t(), String.t()) :: [dropped_command_execution()]
  defdelegate drop_node_command_executions(node_id, cluster_name), to: CommandExecutionLifecycle

  @doc "Publishes events for executions dropped during node cleanup."
  @spec publish_dropped_command_executions([dropped_command_execution()]) :: :ok
  defdelegate publish_dropped_command_executions(dropped_command_executions), to: CommandExecutionLifecycle

  @doc "Acknowledges command execution receipt from an agent."
  @spec acknowledge_command_execution(CommandExecution.t(), map()) ::
          {:ok, CommandExecution.t()}
          | {:error, {:conflict, String.t()}}
          | {:error, Ecto.Changeset.t()}
  defdelegate acknowledge_command_execution(execution, params), to: CommandExecutionLifecycle

  @doc "Updates a command execution with an agent-reported result."
  @spec update_command_execution_result(CommandExecution.t(), map()) ::
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()}
  defdelegate update_command_execution_result(execution, params), to: CommandExecutionLifecycle

  @doc "Cancels a command execution."
  @spec cancel_command_execution(CommandExecution.t()) ::
          {:ok, {:cancelled, CommandExecution.t()} | :accepted}
          | {:error, {:conflict, String.t()}}
          | {:error, :service_unavailable}
  defdelegate cancel_command_execution(execution), to: CommandExecutionLifecycle

  @doc "Expires stale command executions owned by this Admin."
  @spec expire_stale_command_executions() :: :ok
  defdelegate expire_stale_command_executions(), to: Retention

  @doc "Deletes finalized command executions older than the retention period."
  @spec prune_command_executions(pos_integer()) :: {:ok, non_neg_integer()}
  defdelegate prune_command_executions(retention_days), to: Retention
end
