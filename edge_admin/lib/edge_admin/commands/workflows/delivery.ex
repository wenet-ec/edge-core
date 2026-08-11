# edge_admin/lib/edge_admin/commands/workflows/dispatch.ex
defmodule EdgeAdmin.Commands.Workflows.Dispatch do
  @moduledoc """
  Owns command fan-out and delivery.

  This workflow validates targeting, creates execution rows for matching nodes,
  and delivers pending executions to healthy nodes owned by the current Admin.
  """

  import Ecto.Query, warn: false

  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.Commands
  alias EdgeAdmin.Commands.Forms
  alias EdgeAdmin.Commands.Schemas.Command
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Commands.Workers.CreateExecutionsWorker
  alias EdgeAdmin.Commands.Workflows.ExecutionLifecycle
  alias EdgeAdmin.EdgeClusters.AgentClient
  alias EdgeAdmin.Events
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Nodes.Targeting
  alias EdgeAdmin.Repo

  require Logger

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
         {:ok, command} <- Commands.create_command(attrs) do
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
  - `node_filters` - Optional filters for nodes (status, version, self_update_enabled)
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

    case Commands.get_command(command_id) do
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
          case ExecutionLifecycle.transition_status(execution, [:pending],
                 status: :sent,
                 sent_at: DateTime.truncate(DateTime.utc_now(), :second)
               ) do
            {:ok, updated} ->
              ExecutionLifecycle.publish_execution_event(updated, :sent)

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
end
