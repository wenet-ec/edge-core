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
      (see `Checks.ExecutionAcceptsResultCheck`)

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

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  alias Ecto.Query.CastError
  alias EdgeAdmin.Commands.Checks
  alias EdgeAdmin.Commands.Filters.CommandFilters
  alias EdgeAdmin.Commands.Filters.ExecutionFilters
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Commands.Workflows.Dispatch
  alias EdgeAdmin.Commands.Workflows.ExecutionLifecycle
  alias EdgeAdmin.Commands.Workflows.Retention
  alias EdgeAdmin.Repo

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
  def get_command(id) do
    case Repo.get(Command, id) do
      nil -> {:error, :not_found}
      command -> {:ok, command}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc """
  Creates a new command.

  ## Parameters
  - `attrs` - Map of command attributes

  ## Returns
  - `{:ok, command}` - Command created successfully
  - `{:error, changeset}` - Validation failed
  """
  @spec create_command(map()) :: {:ok, Command.t()} | {:error, Ecto.Changeset.t()}
  def create_command(attrs \\ %{}) do
    %Command{}
    |> Command.changeset(attrs)
    |> Repo.insert()
  end

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
  def update_command(%Command{} = command, attrs) do
    command
    |> Command.changeset(attrs)
    |> Repo.update()
  end

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
  def delete_command(%Command{} = command) do
    with :ok <- Checks.PendingExecutionsCheck.check(command) do
      Repo.delete(command)
    end
  end

  @doc """
  Returns a changeset for tracking command changes (for forms).

  ## Examples

      iex> change_command(command)
      %Ecto.Changeset{data: %Command{}}
  """
  @spec change_command(Command.t(), map()) :: Ecto.Changeset.t()
  def change_command(%Command{} = command, attrs \\ %{}) do
    Command.changeset(command, attrs)
  end

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
  def list_commands(params \\ %{}) do
    # Parse params into Flop format
    flop_params = EdgeAdmin.RequestParser.parse(params)

    # Extract has_timeout filter (virtual, handle separately)
    {has_timeout_filters, other_filters} =
      Enum.split_with(flop_params[:filters] || [], fn filter ->
        filter.field == :has_timeout
      end)

    # Extract has_expires_at filter (virtual, handle separately)
    {has_expires_at_filters, other_filters} =
      Enum.split_with(other_filters, fn filter ->
        filter.field == :has_expires_at
      end)

    {ilike_filters, flop_params} =
      EdgeAdmin.RequestParser.split_ilike_filters(
        Map.put(flop_params, :filters, other_filters),
        [:command_text]
      )

    base_query =
      Enum.reduce(ilike_filters, Command, fn %{field: field, value: value}, acc ->
        from(c in acc, where: case_insensitive_like(field(c, ^field), ^value))
      end)

    base_query = CommandFilters.apply_has_timeout(base_query, has_timeout_filters)
    base_query = CommandFilters.apply_has_expires_at(base_query, has_expires_at_filters)

    case Flop.validate_and_run(base_query, flop_params,
           for: Command,
           replace_invalid_params: true
         ) do
      {:ok, {commands, meta}} ->
        {:ok, {commands, meta}}

      {:error, meta} ->
        {:error, meta}
    end
  end

  @doc """
  Gets a single command execution by ID.

  ## Parameters
  - `id` - The execution's UUID

  ## Returns
  - `{:ok, execution}` - Execution found (with command preloaded)
  - `{:error, :not_found}` - Execution doesn't exist or invalid UUID
  """
  @spec get_command_execution(String.t()) :: {:ok, CommandExecution.t()} | {:error, :not_found}
  def get_command_execution(id) do
    case Repo.get(CommandExecution, id) do
      nil -> {:error, :not_found}
      command_execution -> {:ok, Repo.preload(command_execution, :command)}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc """
  Creates a new command execution.

  ## Parameters
  - `attrs` - Map of execution attributes

  ## Returns
  - `{:ok, execution}` - Execution created successfully
  - `{:error, changeset}` - Validation failed
  """
  @spec create_command_execution(map()) :: {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()}
  def create_command_execution(attrs \\ %{}) do
    result =
      %CommandExecution{}
      |> CommandExecution.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, execution} -> {:ok, execution}
      error -> error
    end
  end

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
  def update_command_execution(%CommandExecution{} = command_execution, attrs) do
    command_execution
    |> CommandExecution.changeset(attrs)
    |> Repo.update()
  end

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
  def delete_command_execution(%CommandExecution{} = command_execution) do
    with :ok <- Checks.ExecutionTerminalCheck.check(command_execution) do
      Repo.delete(command_execution)
    end
  end

  @doc """
  Returns a changeset for tracking execution changes (for forms).

  ## Examples

      iex> change_command_execution(execution)
      %Ecto.Changeset{data: %CommandExecution{}}
  """
  @spec change_command_execution(CommandExecution.t(), map()) :: Ecto.Changeset.t()
  def change_command_execution(%CommandExecution{} = command_execution, attrs \\ %{}) do
    CommandExecution.changeset(command_execution, attrs)
  end

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
  def list_command_executions(params \\ %{}) do
    flop_params = EdgeAdmin.RequestParser.parse(params)
    {custom, ilike_filters, flop_params} = split_execution_filters(flop_params)

    base_query =
      from(ce in CommandExecution,
        left_join: n in assoc(ce, :node),
        left_join: c in assoc(n, :cluster),
        preload: [:command, :cluster, node: :cluster]
      )

    query =
      base_query
      |> ExecutionFilters.apply_command_ids(custom.command_id)
      |> ExecutionFilters.apply_cluster_name(custom.cluster_name)
      |> ExecutionFilters.apply_node_ids(custom.node_id)
      |> ExecutionFilters.apply_has_cluster(custom.has_cluster)
      |> ExecutionFilters.apply_has_output(custom.has_output)

    query_with_ilike =
      Enum.reduce(ilike_filters, query, fn %{field: field, value: value}, acc ->
        from(ce in acc, where: case_insensitive_like(field(ce, ^field), ^value))
      end)

    # Run Flop query
    case Flop.validate_and_run(query_with_ilike, flop_params,
           for: CommandExecution,
           replace_invalid_params: true
         ) do
      {:ok, {command_executions, meta}} ->
        {:ok, {command_executions, meta}}

      {:error, meta} ->
        {:error, meta}
    end
  end

  defp split_execution_filters(flop_params) do
    custom_fields = [:command_id, :cluster_name, :node_id, :has_cluster, :has_output]

    {custom_filters, rest} =
      Enum.split_with(flop_params[:filters] || [], fn f -> f.field in custom_fields end)

    custom = Map.new(custom_fields, fn field -> {field, Enum.filter(custom_filters, &(&1.field == field))} end)

    {ilike_filters, flop_params} =
      EdgeAdmin.RequestParser.split_ilike_filters(Map.put(flop_params, :filters, rest), [:output])

    {custom, ilike_filters, flop_params}
  end

  @doc "Creates a command and enqueues execution creation."
  @spec create_command_and_executions(map()) :: {:ok, Command.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_command_and_executions(params), to: Dispatch

  @doc "Creates command executions from targeting arguments."
  @spec create_command_executions(map()) :: {:ok, [CommandExecution.t()]} | {:error, String.t()}
  defdelegate create_command_executions(args), to: Dispatch

  @doc "Delivers pending executions for clusters owned by this Admin."
  @spec deliver_local_executions() :: :ok
  defdelegate deliver_local_executions(), to: Dispatch

  @type dropped_execution :: ExecutionLifecycle.dropped_execution()

  @doc "Marks pending or sent executions for a node as dropped."
  @spec drop_node_executions(String.t(), String.t()) :: [dropped_execution()]
  defdelegate drop_node_executions(node_id, cluster_name), to: ExecutionLifecycle

  @doc "Publishes events for executions dropped during node cleanup."
  @spec publish_dropped_executions([dropped_execution()]) :: :ok
  defdelegate publish_dropped_executions(dropped_executions), to: ExecutionLifecycle

  @doc "Acknowledges command execution receipt from an agent."
  @spec acknowledge_execution(CommandExecution.t(), map()) ::
          {:ok, CommandExecution.t()}
          | {:error, {:conflict, String.t()}}
          | {:error, Ecto.Changeset.t()}
  defdelegate acknowledge_execution(execution, params), to: ExecutionLifecycle

  @doc "Updates a command execution with an agent-reported result."
  @spec update_command_execution_result(CommandExecution.t(), map()) ::
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()}
  defdelegate update_command_execution_result(execution, params), to: ExecutionLifecycle

  @doc "Cancels a command execution."
  @spec cancel_command_execution(CommandExecution.t()) ::
          {:ok, {:cancelled, CommandExecution.t()} | :accepted}
          | {:error, {:conflict, String.t()}}
          | {:error, :service_unavailable}
  defdelegate cancel_command_execution(execution), to: ExecutionLifecycle

  @doc "Expires stale command executions owned by this Admin."
  @spec expire_stale_executions() :: :ok
  defdelegate expire_stale_executions(), to: Retention

  @doc "Deletes finalized command executions older than the retention period."
  @spec prune_executions(pos_integer()) :: {:ok, non_neg_integer()}
  defdelegate prune_executions(retention_days), to: Retention
end
