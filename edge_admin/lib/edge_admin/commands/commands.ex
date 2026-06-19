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
    - Terminal states: `completed` | `cancelled` | `expired`
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
      {:ok, %{result: "cancellation request sent"}}
  """

  import Ecto.Query, warn: false
  import EdgeAdmin.Query, only: [case_insensitive_like: 2]

  alias Ecto.Query.CastError
  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.Commands.Checks
  alias EdgeAdmin.Commands.Filters.CommandFilters
  alias EdgeAdmin.Commands.Filters.ExecutionFilters
  alias EdgeAdmin.Commands.Forms
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Commands.Workers.CreateExecutionsWorker
  alias EdgeAdmin.EdgeClusters.AgentClient
  alias EdgeAdmin.EdgeClusters.Gateway
  alias EdgeAdmin.Events
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Targeting
  alias EdgeAdmin.Repo

  require Logger

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
  - `{:error, {:conflict, reason}}` - Command has non-completed executions
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
  - `status` - Enum IN: `"pending"`, `"sent"`, `"completed"`, `"cancelled"`, `"expired"` — single value or comma-separated list for multi-match
  - `target_all` - Boolean
  - `exit_code` - Exact, `__gte`, `__lte`
  - `command_ids` - Exact IN match on command IDs (comma-separated on REST, array on MCP)
  - `node_ids` - Exact IN match on node IDs (comma-separated on REST, array on MCP)
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
        join: n in assoc(ce, :node),
        join: c in assoc(n, :cluster),
        preload: [:command, :cluster, node: :cluster]
      )

    query =
      base_query
      |> ExecutionFilters.apply_command_ids(custom.command_ids)
      |> ExecutionFilters.apply_cluster_name(custom.cluster_name)
      |> ExecutionFilters.apply_node_ids(custom.node_ids)
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
    custom_fields = [:command_ids, :cluster_name, :node_ids, :has_cluster, :has_output]

    {custom_filters, rest} =
      Enum.split_with(flop_params[:filters] || [], fn f -> f.field in custom_fields end)

    custom = Map.new(custom_fields, fn field -> {field, Enum.filter(custom_filters, &(&1.field == field))} end)

    {ilike_filters, flop_params} =
      EdgeAdmin.RequestParser.split_ilike_filters(Map.put(flop_params, :filters, rest), [:output])

    {custom, ilike_filters, flop_params}
  end

  @doc """
  Creates a command and enqueues execution creation job.

  Takes command attributes including targeting specification and creates
  the command record, then enqueues a background job to create executions
  for the targeted nodes.

  ## Parameters

  - `attrs` - Map containing:
    - `command_text` - The command to execute
    - `targeting` - Targeting specification:
      - `type` - One of "all", "nodes", or "clusters"
      - `node_ids` - List of node IDs (required for "nodes" type)
      - `cluster_names` - List of cluster names (required for "clusters" type)
      - `node_filters` - Optional filters (map)
      - `cluster_filters` - Optional filters for "all"/"clusters" types (map)

  ## Returns

  - `{:ok, command}` - Command created successfully
  - `{:error, changeset}` - Validation failed
  """
  @spec create_command_and_executions(map()) :: {:ok, Command.t()} | {:error, Ecto.Changeset.t()}
  def create_command_and_executions(params) do
    with {:ok, attrs} <- Forms.CreateCommandForm.changeset(params),
         {:ok, command} <- create_command(attrs) do
      enqueue_execution_creation(command, attrs)
      {:ok, command}
    else
      {:error, changeset} ->
        Logger.error("Failed to create command: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp enqueue_execution_creation(command, %{"targeting" => targeting}) do
    targeting_type = targeting["type"]

    args =
      case targeting_type do
        "all" ->
          %{
            command_id: command.id,
            targeting_type: "all",
            node_filters: Map.get(targeting, "node_filters", %{}),
            cluster_filters: Map.get(targeting, "cluster_filters", %{})
          }

        "nodes" ->
          %{
            command_id: command.id,
            targeting_type: "nodes",
            node_ids: Map.get(targeting, "node_ids", []),
            node_filters: Map.get(targeting, "node_filters", %{})
          }

        "clusters" ->
          %{
            command_id: command.id,
            targeting_type: "clusters",
            cluster_names: Map.get(targeting, "cluster_names", []),
            node_filters: Map.get(targeting, "node_filters", %{}),
            cluster_filters: Map.get(targeting, "cluster_filters", %{})
          }

        _ ->
          Logger.warning("Invalid targeting type for command #{command.id}: #{inspect(targeting)}")

          nil
      end

    if args do
      args
      |> CreateExecutionsWorker.new()
      |> Oban.insert()
      |> case do
        {:ok, _job} ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to enqueue CreateExecutionsWorker: #{inspect(reason)}")
      end
    else
      :ok
    end
  end

  defp enqueue_execution_creation(command, attrs) do
    Logger.warning("No targeting specification found for command #{command.id}, attrs: #{inspect(attrs)}")

    :ok
  end

  @doc """
  Creates command executions based on targeting args.

  Unified function that handles "all", "nodes", and "clusters" targeting types.
  All validation and filtering happens here - the worker just passes args.

  ## Args Structure

  - `command_id` - The command ID
  - `targeting_type` - Either "all", "nodes", or "clusters"
  - `node_filters` - Optional filters for nodes (status, id_type, version, self_update_enabled)
  - `cluster_filters` - Optional filters for clusters (name, ipv4_range, node_count)
  - `node_ids` - Required for "nodes" type, list of specific node IDs
  - `cluster_names` - Required for "clusters" type, list of cluster names

  ## Behavior

  - Creates executions for ALL matching nodes (regardless of health status)
  - Delivery will only happen to healthy nodes (filtered during delivery phase)
  - All executions created with status `:pending`
  - Uses bulk insert for efficiency
  - Returns {:ok, executions} or {:error, reason}
  """
  @spec create_command_executions(map()) :: {:ok, [CommandExecution.t()]} | {:error, String.t()}
  def create_command_executions(args) do
    command_id = args["command_id"]
    targeting_type = args["targeting_type"]
    node_filters = args["node_filters"] || %{}
    cluster_filters = args["cluster_filters"] || %{}

    case get_command(command_id) do
      {:ok, command} ->
        # Get nodes based on targeting type
        {nodes, cluster_id} =
          case targeting_type do
            "all" ->
              {Targeting.nodes_for_all(node_filters, cluster_filters), nil}

            "nodes" ->
              node_ids = args["node_ids"] || []
              {Targeting.nodes_for_ids(node_ids, node_filters), nil}

            "clusters" ->
              cluster_names = args["cluster_names"] || []
              Targeting.nodes_for_clusters(cluster_names, node_filters, cluster_filters)

            _ ->
              Logger.error("Invalid targeting type: #{targeting_type}")
              {[], nil}
          end

        if Enum.empty?(nodes) do
          Logger.info("No matching nodes found for command #{command_id}")
          {:ok, []}
        else
          bulk_create_executions(
            command,
            nodes,
            targeting_type == "all",
            cluster_id,
            targeting_type
          )
        end

      {:error, :not_found} ->
        Logger.error("Command not found: #{command_id}")
        {:error, "Command not found"}
    end
  end

  defp bulk_create_executions(command, nodes, target_all, cluster_id, targeting_type) do
    Logger.info("Creating executions for #{length(nodes)} node(s)")

    now = DateTime.truncate(DateTime.utc_now(), :second)

    executions =
      Enum.map(nodes, fn node ->
        %{
          id: Uniq.UUID.uuid7(),
          command_id: command.id,
          node_id: node.id,
          cluster_id: cluster_id,
          target_all: target_all,
          status: :pending,
          inserted_at: now,
          updated_at: now
        }
      end)

    try do
      {count, inserted_executions} =
        Repo.insert_all(CommandExecution, executions, returning: true)

      Logger.info("Successfully created #{count} command executions")

      # Emit telemetry for each execution created
      Enum.each(1..count, fn _ ->
        :telemetry.execute(
          [:edge_admin, :commands, :execution, :created],
          %{count: 1, total: 1},
          %{targeting_type: targeting_type}
        )
      end)

      # Publish execution.created events — nodes already have cluster preloaded
      cluster_name_by_node_id = Map.new(nodes, fn node -> {node.id, node.cluster && node.cluster.name} end)

      Enum.each(inserted_executions, fn execution ->
        cluster_name = Map.get(cluster_name_by_node_id, execution.node_id)

        Events.publish(%Catalog.CommandExecutionCreated{
          execution: execution,
          command: command,
          cluster_name: cluster_name
        })
      end)

      {:ok, inserted_executions}
    rescue
      exception ->
        Logger.error("Failed to bulk insert executions: #{Exception.message(exception)}")
        {:error, Exception.message(exception)}
    end
  end

  @doc """
  Delivers pending command executions for clusters owned by this admin.

  Called by the Quantum LocalScheduler on the `EXECUTION_DELIVERY_SCHEDULE`
  cadence (default: every minute). Uses local metadata to determine
  which clusters this admin owns, then delivers pending executions directly to agents.

  ## Behavior

  - Only processes executions for nodes in clusters owned by this admin
  - Delivers executions in FIFO order per node
  - Uses Task.async_stream for parallel delivery across nodes
  - Admin sends HTTP requests directly to agents (no Gateway intermediary)
  - Continues processing all executions even if some fail

  ## Returns

  Always returns `:ok` - errors are logged but don't halt the scheduler.
  """
  @spec deliver_local_executions() :: :ok
  def deliver_local_executions do
    # Get clusters owned by this admin from metadata (ETS)
    my_clusters = Metadata.get_my_clusters()
    my_cluster_network_names = Map.keys(my_clusters)

    Logger.debug("Execution delivery - my_clusters: #{inspect(my_clusters)}")

    Logger.debug("Execution delivery - my_cluster_network_names: #{inspect(my_cluster_network_names)}")

    if Enum.empty?(my_cluster_network_names) do
      Logger.debug("No clusters assigned to this admin, skipping execution delivery")

      # Emit telemetry
      :telemetry.execute(
        [:edge_admin, :commands, :delivery],
        %{delivered_count: 0},
        %{result: :skipped}
      )

      :ok
    else
      # Strip "cluster-" prefix to get DB cluster names
      my_cluster_names =
        Enum.map(my_cluster_network_names, fn network_name ->
          String.replace_prefix(network_name, "cluster-", "")
        end)

      Logger.debug("Querying pending executions for clusters: #{inspect(my_cluster_names)}")

      # Query pending executions for MY nodes only
      pending_executions = get_pending_executions_for_my_clusters(my_cluster_names)

      Logger.debug("Found #{length(pending_executions)} pending executions")

      if Enum.empty?(pending_executions) do
        Logger.debug("No pending executions to deliver")

        # Emit telemetry
        :telemetry.execute(
          [:edge_admin, :commands, :delivery],
          %{delivered_count: 0},
          %{result: :success}
        )

        :ok
      else
        # Group by node for FIFO processing
        executions_by_node = Enum.group_by(pending_executions, & &1.node_id)

        Logger.info(
          "Delivering #{length(pending_executions)} pending executions across #{map_size(executions_by_node)} nodes"
        )

        # Process nodes in parallel
        executions_by_node
        |> Task.async_stream(
          fn {_node_id, executions} ->
            node = hd(executions).node
            deliver_executions_to_node(node, executions)
          end,
          max_concurrency: 50,
          timeout: 30_000,
          on_timeout: :kill_task
        )
        |> Stream.run()

        Logger.info("Completed execution delivery")

        # Emit telemetry
        :telemetry.execute(
          [:edge_admin, :commands, :delivery],
          %{delivered_count: length(pending_executions)},
          %{result: :success}
        )

        :ok
      end
    end
  end

  defp get_pending_executions_for_my_clusters(cluster_names) do
    now = DateTime.utc_now()

    Repo.all(
      from(ce in CommandExecution,
        join: n in assoc(ce, :node),
        join: c in assoc(n, :cluster),
        join: cmd in assoc(ce, :command),
        where: ce.status == :pending,
        where: c.name in ^cluster_names,
        where: n.status == :healthy,
        where: is_nil(cmd.expires_at) or cmd.expires_at > ^now,
        order_by: [asc: ce.node_id, asc: ce.inserted_at],
        preload: [node: :cluster, command: []]
      )
    )
  end

  defp deliver_executions_to_node(node, executions) do
    # Deliver all executions - don't stop on failures
    Logger.info("Delivering #{length(executions)} executions to node #{node.id}")

    Enum.each(executions, fn execution ->
      execution_data = %{
        id: execution.id,
        command_id: execution.command_id,
        node_id: execution.node_id,
        command_text: CommandExecution.command_text(execution),
        timeout: CommandExecution.timeout(execution),
        expires_at: CommandExecution.expires_at(execution),
        status: "pending"
      }

      case AgentClient.deliver_execution(node, execution_data) do
        {:ok, :sent} ->
          # Agent received it — conditional transition pending → sent.
          # If the row is no longer :pending (agent already reported back, admin
          # cancelled/expired, or a peer admin already marked it sent), do not
          # overwrite. See `transition_status/3`.
          case transition_status(execution, [:pending],
                 status: :sent,
                 sent_at: DateTime.truncate(DateTime.utc_now(), :second)
               ) do
            {:ok, updated} ->
              publish_execution_event(updated, :sent)

            {:error, :stale_state} ->
              Logger.debug(
                "Skipped sent transition for execution #{execution.id}: row no longer in :pending (likely already reported by agent or transitioned by peer admin)"
              )
          end

          :telemetry.execute(
            [:edge_admin, :commands, :execution, :delivered],
            %{count: 1, total: 1},
            %{result: :success}
          )

        {:error, reason} ->
          Logger.warning("Failed to deliver execution #{execution.id} to node #{node.id}: #{inspect(reason)}")

          :telemetry.execute(
            [:edge_admin, :commands, :execution, :delivered],
            %{count: 1, total: 1},
            %{result: :failure}
          )
      end
    end)

    :ok
  end

  @doc """
  Acknowledges command execution receipt from agent.

  Validates execution is in `:pending` status and transitions it to `:sent`.
  Called when agent receives and stores a pending command execution.

  ## Parameters
  - `execution` - The execution struct
  - `params` - Currently unused; accepted for symmetry with the controller surface.
    Pass `%{}` from new call sites.

  ## Returns
  - `{:ok, execution}` - Acknowledgment succeeded
  - `{:error, {:conflict, reason}}` - Execution not in `:pending` status
  - `{:error, changeset}` - Status update failed validation

  ## Examples

      iex> acknowledge_execution(execution, %{})
      {:ok, %CommandExecution{status: :sent}}
  """
  @spec acknowledge_execution(CommandExecution.t(), map()) ::
          {:ok, CommandExecution.t()}
          | {:error, {:conflict, String.t()}}
          | {:error, Ecto.Changeset.t()}
  def acknowledge_execution(execution, _params) do
    with :ok <- Checks.ExecutionPendingCheck.check(execution),
         {:ok, updated} <-
           transition_status(execution, [:pending],
             status: :sent,
             sent_at: DateTime.truncate(DateTime.utc_now(), :second)
           ) do
      publish_execution_event(updated, :sent)
      {:ok, updated}
    else
      {:error, :stale_state} ->
        # Row moved out of :pending between the check and the write — surface
        # the same 409 the check would have produced if it had won the race.
        {:error, {:conflict, "execution is no longer in 'pending' status and cannot be acknowledged"}}

      other ->
        other
    end
  end

  @doc """
  Updates command execution result from agent.

  Validates execution status and updates with the agent-reported result. The
  agent is the source of truth for terminal status: an `exit_code: 143`
  (SIGTERM) is rewritten to `:cancelled`, an agent-reported `status: :expired`
  passes through, and everything else is recorded as `:completed`.

  ## Parameters
  - `execution` - The execution struct
  - `params` - Map with:
    - `"status"` (required) — `"completed"` or `"expired"` (wire-format string from agent)
    - `"output"` (optional) — command stdout/stderr text
    - `"exit_code"` (optional) — integer; 143 forces cancelled, 124 categorised as timeout
    - `"completed_at"` (optional) — ISO 8601 datetime; defaults to now

  ## Returns
  - `{:ok, execution}` - Update succeeded
  - `{:error, changeset}` - Validation failed
  - `{:error, {:conflict, reason}}` - Execution not in a state that accepts a result

  ## Examples

      iex> update_command_execution_result(execution, %{
      ...>   "status" => "completed",
      ...>   "output" => "Command output",
      ...>   "exit_code" => 0
      ...> })
      {:ok, %CommandExecution{status: :completed, exit_code: 0}}
  """
  @spec update_command_execution_result(CommandExecution.t(), map()) ::
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()}
  def update_command_execution_result(execution, params) do
    with :ok <- Checks.ExecutionAcceptsResultCheck.check(execution),
         {:ok, attrs} <- Forms.UpdateCommandExecutionResultForm.changeset(params) do
      # Agent is the source of truth for terminal status.
      # exit_code 143 (SIGTERM) means the agent honoured a cancellation request — override to :cancelled.
      # :expired means agent detected expiry before running — trust it.
      # Everything else is recorded as :completed.
      terminal_status =
        cond do
          attrs["exit_code"] == 143 -> :cancelled
          attrs["status"] == :expired -> :expired
          true -> :completed
        end

      # Conditional transition: only write if the row is still in a state that
      # accepts a result. The race-window allowance from
      # `ExecutionAcceptsResultCheck` (cancelled/expired with nil exit_code) is
      # encoded directly in the WHERE clause so two concurrent reports cannot
      # both succeed and clobber each other.
      result = transition_to_result(execution, build_result_set(attrs, terminal_status))

      # Emit completion telemetry
      case result do
        {:ok, updated_execution} ->
          # Calculate duration from sent_at to now
          duration_ms =
            if execution.sent_at do
              DateTime.diff(DateTime.utc_now(), execution.sent_at, :millisecond)
            else
              0
            end

          # Categorize exit code
          exit_code_category =
            cond do
              updated_execution.exit_code == 0 -> :success
              updated_execution.exit_code == 143 -> :cancelled
              updated_execution.exit_code == 124 -> :timeout
              updated_execution.exit_code > 0 -> :failure
              true -> :unknown
            end

          :telemetry.execute(
            [:edge_admin, :commands, :execution, :completed],
            %{duration: duration_ms},
            %{exit_code_category: exit_code_category}
          )

          event_type = if terminal_status == :cancelled, do: :cancelled, else: :completed
          publish_execution_event(updated_execution, event_type)

        _ ->
          :ok
      end

      case result do
        {:error, :stale_state} ->
          # Row was already in a terminal-with-exit_code state by the time we
          # tried to write. Treat as a 409 — the agent has already reported a
          # result (possibly via a different admin) and should not retry.
          {:error, {:conflict, "execution is no longer in a state that accepts a result (likely already reported)"}}

        other ->
          other
      end
    end
  end

  # Build the `update_all set:` keyword list from the form-normalised attrs
  # map. The form guarantees `completed_at` is a %DateTime{} and that
  # `output`/`exit_code` are either present-with-a-value or absent.
  defp build_result_set(attrs, terminal_status) do
    base = [
      status: terminal_status,
      completed_at: DateTime.truncate(attrs["completed_at"], :second)
    ]

    base
    |> maybe_put(:output, Map.get(attrs, "output"))
    |> maybe_put(:exit_code, Map.get(attrs, "exit_code"))
    |> maybe_put(
      :cancelled_at,
      terminal_status == :cancelled && DateTime.truncate(DateTime.utc_now(), :second)
    )
  end

  defp maybe_put(set, _key, nil), do: set
  defp maybe_put(set, _key, false), do: set
  defp maybe_put(set, key, value), do: Keyword.put(set, key, value)

  @doc """
  Cancels a command execution.

  Handles two scenarios:
  1. Pending — Updates DB status to `:cancelled` immediately (command never
     reached the agent, no output / exit code).
  2. Sent — Sends best-effort cancellation request to agent via Gateway. The
     row's status is left as `:sent` until the agent reports back (which may
     be `:cancelled` or, if the agent already finished, `:completed`).

  ## Parameters
    - execution: CommandExecution struct (must be preloaded with :cluster)

  ## Returns
    - `{:ok, %{result: "execution cancelled"}}` — pending branch, DB updated
    - `{:ok, %{result: "cancellation request sent"}}` — sent branch, agent reachable
    - `{:error, {:conflict, reason}}` — execution not in cancellable state
    - `{:error, :service_unavailable}` — agent unreachable (sent branch only)
  """
  @spec cancel_command_execution(CommandExecution.t()) ::
          {:ok, map()} | {:error, {:conflict, String.t()}} | {:error, :service_unavailable}
  def cancel_command_execution(execution) do
    with :ok <- Checks.ExecutionCancellableCheck.check(execution) do
      case execution.status do
        :pending ->
          # Conditional cancel: only flip pending → cancelled. If a peer admin
          # or this admin's scheduler moved the row to :sent in the meantime,
          # fall through to the :sent branch and ask the agent to cancel.
          case transition_status(execution, [:pending],
                 status: :cancelled,
                 cancelled_at: DateTime.truncate(DateTime.utc_now(), :second)
               ) do
            {:ok, updated} ->
              publish_execution_event(updated, :cancelled)
              {:ok, %{result: "execution cancelled"}}

            {:error, :stale_state} ->
              case Repo.get(CommandExecution, execution.id) do
                %CommandExecution{status: :sent} = current ->
                  cancel_sent_execution(current)

                _ ->
                  {:error, {:conflict, "execution is no longer cancellable"}}
              end
          end

        :sent ->
          cancel_sent_execution(execution)
      end
    end
  end

  @doc """
  Expires all stale command executions whose command's `expires_at` has passed.

  Called by the Quantum scheduler (every minute). Processes executions in two passes:

  - `pending` - Command never reached the agent; mark expired immediately in DB.
  - `sent` - Command was delivered; send best-effort cancellation to agent, then mark
    expired in DB regardless of whether the agent acknowledged it. If the agent already
    ran the command and reports back later, `ExecutionAcceptsResultCheck` will accept the
    result and overwrite the expired status (agent is source of truth for what ran).

  Always returns `:ok` — errors are logged but never halt the scheduler.
  """
  @spec expire_stale_executions() :: :ok
  def expire_stale_executions do
    now = DateTime.utc_now()

    # Scope to clusters owned by this admin. Without this gate, every admin in
    # the fleet runs the expiration loop against every cluster every minute,
    # producing write amplification and (pre-conditional-update) clobbering
    # terminal rows. Mirrors the ownership gate in `deliver_local_executions/0`.
    my_cluster_names =
      Metadata.get_my_clusters()
      |> Map.keys()
      |> Enum.map(&String.replace_prefix(&1, "cluster-", ""))

    stale_executions =
      if my_cluster_names == [] do
        []
      else
        get_stale_executions(now, my_cluster_names)
      end

    if Enum.empty?(stale_executions) do
      Logger.debug("No stale executions to expire")
      :ok
    else
      Logger.info("Expiring #{length(stale_executions)} stale execution(s)")

      Enum.each(stale_executions, fn execution ->
        case execution.status do
          :pending ->
            expire_execution(execution, now)

          :sent ->
            # Best-effort cancel signal to agent — do not block on result
            case send_cancel_to_agent(execution) do
              :ok ->
                Logger.debug("Sent cancellation to agent for expiring execution #{execution.id}")

              {:error, reason} ->
                Logger.warning(
                  "Could not reach agent for expiring execution #{execution.id}: #{inspect(reason)} — marking expired anyway"
                )
            end

            expire_execution(execution, now)
        end
      end)

      :telemetry.execute(
        [:edge_admin, :commands, :expiration],
        %{expired_count: length(stale_executions)},
        %{}
      )

      :ok
    end
  end

  defp get_stale_executions(now, cluster_names) do
    cancellable = CommandExecution.cancellable_statuses()

    Repo.all(
      from(ce in CommandExecution,
        join: c in assoc(ce, :command),
        join: n in assoc(ce, :node),
        join: cl in assoc(n, :cluster),
        where: ce.status in ^cancellable,
        where: not is_nil(c.expires_at),
        where: c.expires_at <= ^now,
        where: cl.name in ^cluster_names,
        preload: [node: :cluster, command: []]
      )
    )
  end

  defp expire_execution(execution, _now) do
    # Conditional transition: only expire rows still in :pending or :sent. If
    # the agent has already reported back (row is now :completed/:cancelled/
    # :expired with exit_code), do not overwrite — the agent is the source of
    # truth for what actually ran.
    case transition_status(execution, [:pending, :sent], status: :expired) do
      {:ok, updated} ->
        Logger.info("Execution #{execution.id} marked expired")
        publish_execution_event(updated, :expired)

      {:error, :stale_state} ->
        Logger.debug(
          "Skipped expire transition for execution #{execution.id}: row already left :pending/:sent (agent reported back)"
        )
    end
  end

  @prune_batch_size 1_000

  @doc """
  Deletes finalised command executions older than `retention_days`.

  An execution is considered finalised — meaning it can no longer receive any
  updates — when:

    * `status == :completed` (agent reported result), or
    * `status in [:cancelled, :expired]` AND `exit_code IS NOT NULL` (agent
      reported the result of the cancel/expire signal).

  A `:cancelled` or `:expired` row with `nil exit_code` is NOT finalised — it's
  a race-window placeholder that `ExecutionAcceptsResultCheck` still accepts a
  late agent report for (the agent picked the command up before the admin's
  cancel/expire reached it). Pruning those would lose the agent's actual
  result if it eventually arrived. We exclude them, regardless of age.

  In-flight executions (`:pending`, `:sent`) are never deleted.

  Deletes in batches of #{@prune_batch_size} to avoid long locks on the hot path.
  Returns `{:ok, total_deleted}`.
  """
  @spec prune_executions(pos_integer()) :: {:ok, non_neg_integer()}
  def prune_executions(retention_days) when is_integer(retention_days) and retention_days > 0 do
    cutoff = DateTime.add(DateTime.utc_now(), -retention_days * 86_400, :second)
    total = prune_loop(cutoff, 0)
    {:ok, total}
  end

  defp prune_loop(cutoff, acc) do
    # Load eligible rows (with command + cluster preloaded for the event) so we
    # can fire `command_execution.pruned` per row before deletion. Then delete
    # by ID. The two-step is intentional: the only async-deletion path in this
    # codebase is pruning, and consumers maintaining state mirrors have no
    # other way to learn that a row went away.
    #
    # Eligibility: completed (always finalised), OR cancelled/expired with
    # exit_code set (agent reported back). Excludes the cancel/expire race
    # window where exit_code is still nil.
    eligible =
      Repo.all(
        from(ce in CommandExecution,
          where:
            ce.inserted_at < ^cutoff and
              (ce.status == :completed or
                 (ce.status in [:cancelled, :expired] and not is_nil(ce.exit_code))),
          limit: @prune_batch_size,
          preload: [:command, node: :cluster]
        )
      )

    case eligible do
      [] ->
        acc

      rows ->
        Enum.each(rows, &enqueue_pruned_event/1)

        ids = Enum.map(rows, & &1.id)
        {deleted, _} = Repo.delete_all(from(ce in CommandExecution, where: ce.id in ^ids))

        if deleted == @prune_batch_size do
          prune_loop(cutoff, acc + deleted)
        else
          acc + deleted
        end
    end
  end

  defp enqueue_pruned_event(execution) do
    cluster_name = execution.node && execution.node.cluster && execution.node.cluster.name

    Events.publish(%Catalog.CommandExecutionPruned{
      execution: execution,
      command: execution.command,
      cluster_name: cluster_name
    })
  end

  # ---------------------------------------------------------------------------
  # Conditional status transitions
  #
  # Every status transition on a CommandExecution flows through one of the two
  # helpers below. The point is to make each transition a single atomic SQL
  # statement (`UPDATE ... WHERE id = ? AND status IN (...)`) so that stale
  # in-memory structs can never overwrite a row that has moved on.
  #
  # Background: this code path runs on every admin in a multi-admin cluster,
  # and ownership of an edge cluster can flap during reconciliation. Without a
  # WHERE-status guard, two admins delivering the same execution (or a single
  # admin whose HTTP round trip is slow enough for the agent to round-trip a
  # result back) can clobber a terminal row back to :sent / :expired. See the
  # incident write-up in the changelog.
  # ---------------------------------------------------------------------------

  @spec transition_status(CommandExecution.t(), [CommandExecution.status()], keyword()) ::
          {:ok, CommandExecution.t()} | {:error, :stale_state}
  defp transition_status(%CommandExecution{id: id}, allowed_from, set) do
    where = dynamic([ce], ce.status in ^allowed_from)
    do_transition(id, where, set)
  end

  # Result-report transition. The "accepts a result" predicate is dynamic:
  # :sent (normal) OR :cancelled / :expired with exit_code IS NULL
  # (race-window placeholders).
  #
  # Paired predicate: the same rule is encoded as a pure struct check in
  # `EdgeAdmin.Commands.Checks.ExecutionAcceptsResultCheck`, which runs first
  # as the layer-3 early-409 gate. This dynamic is the layer-4/5 backstop
  # against concurrent writers the struct check cannot see (peer admin races,
  # agent retries hitting a different admin). If you change the predicate
  # here, change the check there too — the two layers must agree.
  @spec transition_to_result(CommandExecution.t(), keyword()) ::
          {:ok, CommandExecution.t()} | {:error, :stale_state}
  defp transition_to_result(%CommandExecution{id: id}, set) do
    accepts_result =
      dynamic(
        [ce],
        ce.status == :sent or
          (ce.status in [:cancelled, :expired] and is_nil(ce.exit_code))
      )

    do_transition(id, accepts_result, set)
  end

  # Shared core. Runs a conditional `update_all` on the row, and on exactly 1
  # row affected, fetches the fresh struct for event publication. `updated_at`
  # is appended automatically; callers pass only the fields they want to set.
  #
  # We do a follow-up `Repo.get` rather than `update_all returning: [:*]`
  # because the SQLite adapter (DB_ADAPTER=sqlite) does not support RETURNING
  # on `update_all`. Two round trips, identical semantics on both adapters.
  defp do_transition(id, where_dynamic, set) do
    set = Keyword.put(set, :updated_at, DateTime.truncate(DateTime.utc_now(), :second))

    query =
      from(ce in CommandExecution,
        where: ce.id == ^id,
        where: ^where_dynamic
      )

    case Repo.update_all(query, set: set) do
      {1, _} ->
        case Repo.get(CommandExecution, id) do
          nil -> {:error, :stale_state}
          fresh -> {:ok, Repo.preload(fresh, :command)}
        end

      {0, _} ->
        {:error, :stale_state}
    end
  end

  # Extracted shared :sent-branch cancel for use from `cancel_command_execution/1`
  # both directly (when called with a :sent row) and from the fall-through when a
  # :pending row raced to :sent between the check and our conditional update.
  defp cancel_sent_execution(execution) do
    case send_cancel_to_agent(execution) do
      :ok ->
        {:ok, %{result: "cancellation request sent"}}

      {:error, reason} ->
        Logger.warning("Failed to send cancellation to agent for execution #{execution.id}: #{inspect(reason)}")

        {:error, :service_unavailable}
    end
  end

  defp send_cancel_to_agent(execution) do
    # Get node to send cancellation request
    with {:ok, node} <- Nodes.get_node(execution.node_id),
         # Build node name for ETS lookup
         node_name = Node.node_name(node),
         # Lookup cluster name from ETS metadata
         {:ok, cluster_name, _admin_name} <- Metadata.find_node_cluster(node_name),
         # Lookup gateway via ETS metadata
         {:ok, gateway_pid} <- Gateway.lookup(cluster_name),
         # Send cancellation request via Gateway
         :ok <- Gateway.cancel_execution(gateway_pid, node, execution.id) do
      Logger.info("Successfully sent cancellation request to agent for execution #{execution.id}")

      :ok
    else
      {:error, :not_found} ->
        Logger.error("Node not found for execution #{execution.id}")
        {:error, :node_not_found}

      {:error, :gateway_not_found} ->
        Logger.error("Gateway not found for node #{execution.node_id}")
        {:error, :gateway_not_found}

      {:error, :no_owner} ->
        Logger.error("No owner found for node #{execution.node_id}")
        {:error, :no_owner}

      {:error, reason} ->
        Logger.warning("Failed to send cancellation to agent for execution #{execution.id}: #{inspect(reason)}")

        {:error, reason}
    end
  end

  defp publish_execution_event(execution, type) do
    execution = Repo.preload(execution, [:command, node: :cluster], force: true)
    cluster_name = execution.node && execution.node.cluster && execution.node.cluster.name

    event =
      case type do
        :sent ->
          %Catalog.CommandExecutionSent{execution: execution, command: execution.command, cluster_name: cluster_name}

        :completed ->
          %Catalog.CommandExecutionCompleted{
            execution: execution,
            command: execution.command,
            cluster_name: cluster_name
          }

        :cancelled ->
          %Catalog.CommandExecutionCancelled{
            execution: execution,
            command: execution.command,
            cluster_name: cluster_name
          }

        :expired ->
          %Catalog.CommandExecutionExpired{
            execution: execution,
            command: execution.command,
            cluster_name: cluster_name
          }
      end

    Events.publish(event)
  end
end
