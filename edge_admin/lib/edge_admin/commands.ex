# edge_admin/lib/edge_admin/commands.ex
defmodule EdgeAdmin.Commands do
  @moduledoc """
  The Commands context.

  Manages command creation, execution tracking, and provides query helpers
  for the distributed command execution system.
  """

  import Ecto.Query, warn: false

  alias EdgeAdmin.Commands.Command
  alias EdgeAdmin.Commands.CommandExecution
  alias EdgeAdmin.Commands.Workers.ExecutionCreationWorker
  alias EdgeAdmin.FilteringPagination
  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.EdgeClusters.Gateway
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Vpn

  require Logger

  def get_command!(id), do: Repo.get!(Command, id)

  def create_command(attrs \\ %{}) do
    %Command{}
    |> Command.changeset(attrs)
    |> Repo.insert()
  end

  def update_command(%Command{} = command, attrs) do
    command
    |> Command.changeset(attrs)
    |> Repo.update()
  end

  def delete_command(%Command{} = command) do
    Repo.delete(command)
  end

  def change_command(%Command{} = command, attrs \\ %{}) do
    Command.changeset(command, attrs)
  end

  def list_commands_with_filtering_pagination(params \\ %{}) do
    FilteringPagination.paginate(
      Command,
      params,
      filterable_fields: [:command_text],
      sortable_fields: [:inserted_at, :updated_at],
      default_sort: "inserted_at:desc",
      repo: Repo
    )
  end

  defp preload_and_populate_command_text(execution_or_executions) do
    case execution_or_executions do
      # Handle single execution
      %CommandExecution{} = execution ->
        execution
        |> Repo.preload(:command)
        |> CommandExecution.populate_command_text()

      # Handle list of executions
      executions when is_list(executions) ->
        executions
        |> Repo.preload(:command)
        |> Enum.map(&CommandExecution.populate_command_text/1)

      # Handle other cases (shouldn't happen but defensive)
      other ->
        other
    end
  end

  def get_command_execution!(id) do
    CommandExecution
    |> Repo.get!(id)
    |> preload_and_populate_command_text()
  end

  def create_command_execution(attrs \\ %{}) do
    %CommandExecution{}
    |> CommandExecution.changeset(attrs)
    |> Repo.insert()
  end

  def update_command_execution(%CommandExecution{} = command_execution, attrs) do
    command_execution
    |> CommandExecution.changeset(attrs)
    |> Repo.update()
  end

  def delete_command_execution(%CommandExecution{} = command_execution) do
    Repo.delete(command_execution)
  end

  def change_command_execution(%CommandExecution{} = command_execution, attrs \\ %{}) do
    CommandExecution.changeset(command_execution, attrs)
  end

  def list_command_executions_with_filtering_pagination(params \\ %{}) do
    page_result =
      FilteringPagination.paginate(
        CommandExecution,
        params,
        filterable_fields: [:status, :target_all, :exit_code, :command_id, :node_id, :output],
        sortable_fields: [:inserted_at, :updated_at, :status, :sent_at, :completed_at, :exit_code],
        default_sort: "inserted_at:desc",
        repo: Repo
      )

    executions_with_command_text =
      page_result.data
      |> Repo.preload(:command)
      |> Enum.map(&CommandExecution.populate_command_text/1)

    %{page_result | data: executions_with_command_text}
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
      - `type` - Either "all" or "nodes"
      - `node_ids` - List of node IDs (required for "nodes" type)
      - `node_filters` - Optional filters (map)

  ## Returns

  - `{:ok, command}` - Command created successfully
  - `{:error, changeset}` - Validation failed
  """
  def create_command_and_executions(attrs) do
    case create_command(attrs) do
      {:ok, command} ->
        enqueue_execution_creation(command, attrs)
        {:ok, command}

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
            node_filters: Map.get(targeting, "node_filters", %{})
          }

        "nodes" ->
          %{
            command_id: command.id,
            targeting_type: "nodes",
            node_ids: Map.get(targeting, "node_ids", []),
            node_filters: Map.get(targeting, "node_filters", %{})
          }

        _ ->
          Logger.warning(
            "Invalid targeting type for command #{command.id}: #{inspect(targeting)}"
          )

          nil
      end

    if args do
      args
      |> ExecutionCreationWorker.new()
      |> Oban.insert()
      |> case do
        {:ok, _job} ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to enqueue ExecutionCreationWorker: #{inspect(reason)}")
      end
    else
      :ok
    end
  end

  defp enqueue_execution_creation(command, attrs) do
    Logger.warning(
      "No targeting specification found for command #{command.id}, attrs: #{inspect(attrs)}"
    )

    :ok
  end

  @doc """
  Creates command executions based on targeting args.

  Unified function that handles both "all" and "nodes" targeting types.
  All validation and filtering happens here - the worker just passes args.

  ## Args Structure

  - `command_id` - The command ID
  - `targeting_type` - Either "all" or "nodes"
  - `node_filters` - Optional filters for nodes (status, etc.)
  - `node_ids` - Required for "nodes" type, list of specific node IDs

  ## Behavior

  - Only creates executions for nodes with status "healthy"
  - All executions created with status "pending"
  - Uses bulk insert for efficiency
  - Returns {:ok, executions} or {:error, reason}
  """
  def create_command_executions(args) do
    command_id = args["command_id"]
    targeting_type = args["targeting_type"]
    node_filters = args["node_filters"] || %{}

    command = get_command!(command_id)

    # Get nodes based on targeting type
    nodes =
      case targeting_type do
        "all" ->
          get_all_filtered_nodes(node_filters)

        "nodes" ->
          node_ids = args["node_ids"] || []
          get_nodes_for_targeting(node_ids, node_filters)

        _ ->
          Logger.error("Invalid targeting type: #{targeting_type}")
          []
      end

    if Enum.empty?(nodes) do
      Logger.info("No healthy nodes found for command #{command_id}")
      {:ok, []}
    else
      bulk_create_executions(command, nodes, targeting_type == "all")
    end
  end

  defp get_nodes_for_targeting(node_ids, node_filters) do
    unique_node_ids = Enum.uniq(node_ids)

    # Get valid nodes
    nodes =
      unique_node_ids
      |> Nodes.get_nodes_by_ids()
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, node} -> node end)

    # Apply additional filters if provided
    if map_size(node_filters) == 0 do
      # Filter only by healthy status
      Enum.filter(nodes, &(&1.status == "healthy"))
    else
      # Apply both healthy status and custom filters
      all_matching_nodes = get_all_filtered_nodes(node_filters)
      matching_node_ids = MapSet.new(all_matching_nodes, & &1.id)

      Enum.filter(nodes, fn node ->
        node.status == "healthy" and MapSet.member?(matching_node_ids, node.id)
      end)
    end
  end

  defp bulk_create_executions(command, nodes, target_all) do
    Logger.info("Creating executions for #{length(nodes)} healthy nodes")

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    executions =
      Enum.map(nodes, fn node ->
        %{
          command_id: command.id,
          node_id: node.id,
          target_all: target_all,
          status: "pending",
          inserted_at: now,
          updated_at: now
        }
      end)

    try do
      {count, inserted_executions} =
        Repo.insert_all(CommandExecution, executions, returning: true)

      Logger.info("Successfully created #{count} command executions")

      executions_with_command_text =
        Enum.map(inserted_executions, fn execution ->
          %{execution | command_text: command.command_text}
        end)

      {:ok, executions_with_command_text}
    rescue
      exception ->
        Logger.error("Failed to bulk insert executions: #{Exception.message(exception)}")
        {:error, Exception.message(exception)}
    end
  end

  # Helper function to get all nodes across all pages
  defp get_all_filtered_nodes(node_filters, page \\ 1, accumulated_nodes \\ []) do
    params =
      node_filters
      # Only fetch healthy nodes
      |> Map.put("status", "healthy")
      |> Map.put("page_size", "1000")
      |> Map.put("page", to_string(page))

    page_result = Nodes.list_nodes_with_filtering_pagination(params)

    all_nodes = accumulated_nodes ++ page_result.data

    if page_result.has_next do
      get_all_filtered_nodes(node_filters, page + 1, all_nodes)
    else
      all_nodes
    end
  end

  @doc """
  Delivers pending command executions for clusters owned by this admin.

  Called by Quantum scheduler every 10 seconds. Uses local metadata to determine
  which clusters this admin owns, then delivers pending executions via Gateway processes.

  ## Behavior

  - Only processes executions for nodes in clusters owned by this admin
  - Delivers executions in FIFO order per node
  - Uses Task.async_stream for parallel delivery across nodes
  - Stops processing a node on first failure (remaining executions stay pending)
  - Skips nodes that are unhealthy or have no available Gateway

  ## Returns

  Always returns `:ok` - errors are logged but don't halt the scheduler.
  """
  def deliver_local_executions do
    # Get clusters owned by this admin from metadata (ETS)
    my_clusters = Metadata.get_my_clusters()
    my_cluster_network_names = Map.keys(my_clusters)

    Logger.debug("Execution delivery - my_clusters: #{inspect(my_clusters)}")
    Logger.debug("Execution delivery - my_cluster_network_names: #{inspect(my_cluster_network_names)}")

    if Enum.empty?(my_cluster_network_names) do
      Logger.debug("No clusters assigned to this admin, skipping execution delivery")
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
        :ok
      else
        # Group by node for FIFO processing
        executions_by_node = Enum.group_by(pending_executions, & &1.node_id)

        Logger.info(
          "Delivering #{length(pending_executions)} pending executions across #{map_size(executions_by_node)} nodes"
        )

        # Process nodes in parallel (like health check)
        Task.async_stream(
          executions_by_node,
          fn {node_id, executions} ->
            deliver_to_single_node(node_id, executions)
          end,
          max_concurrency: 50,
          timeout: 30_000,
          on_timeout: :kill_task
        )
        |> Stream.run()

        Logger.info("Completed execution delivery")
        :ok
      end
    end
  end

  defp get_pending_executions_for_my_clusters(cluster_names) do
    from(ce in CommandExecution,
      join: n in assoc(ce, :node),
      join: c in assoc(n, :cluster),
      where: ce.status == "pending",
      where: c.name in ^cluster_names,
      where: n.status == "healthy",
      order_by: [asc: ce.node_id, asc: ce.inserted_at],
      preload: [node: :cluster, command: []]
    )
    |> Repo.all()
    |> Enum.map(&CommandExecution.populate_command_text/1)
  end

  defp deliver_to_single_node(node_id, executions) do
    # Get the node (already preloaded from query)
    node = hd(executions).node

    # Double-check node is healthy (metadata might be stale)
    if node.status != "healthy" do
      Logger.debug("Skipping node #{node_id} - status: #{node.status}")
      :skip
    else
      # Lookup local gateway for this cluster
      case lookup_gateway(node) do
        {:ok, gateway_pid} ->
          deliver_executions_via_gateway(gateway_pid, node, executions)

        {:error, :gateway_not_found} ->
          Logger.debug("Gateway not found for cluster #{node.cluster.name}, will retry later")

          :skip
      end
    end
  end

  defp lookup_gateway(node) do
    admin_name = Application.get_env(:edge_admin, :admin_name)
    # Gateway is registered with network name (cluster-xxx), not DB name (xxx)
    cluster_network_name = Vpn.build_network_name(node.cluster.name, prefix: :node)

    case :syn.lookup(:cluster_scope, {:gateway, admin_name, cluster_network_name}) do
      :undefined ->
        {:error, :gateway_not_found}

      {gateway_pid, _meta} ->
        {:ok, gateway_pid}

      gateway_pid when is_pid(gateway_pid) ->
        {:ok, gateway_pid}
    end
  end

  defp deliver_executions_via_gateway(gateway_pid, node, executions) do
    # Deliver executions one by one, stop on first failure
    Enum.reduce_while(executions, :ok, fn execution, :ok ->
      execution_data = %{
        id: execution.id,
        command_id: execution.command_id,
        node_id: execution.node_id,
        command_text: execution.command_text,
        status: "pending"
      }

      case Gateway.create_command_execution(gateway_pid, node, execution_data) do
        {:ok, :sent} ->
          # Agent received it - update to "sent"
          update_command_execution(execution, %{
            status: "sent",
            sent_at: DateTime.utc_now()
          })

          {:cont, :ok}

        {:error, reason} ->
          Logger.warning(
            "Failed to deliver execution #{execution.id} to node #{node.id}: #{inspect(reason)}"
          )

          # Stop processing remaining executions for this node
          {:halt, :error}
      end
    end)
  end

  @doc """
  Lists command executions for a specific node with status "sent".
  Used by agent to fetch pending commands.
  """
  def list_sent_command_executions_for_node(node_id) do
    from(ce in CommandExecution,
      where: ce.node_id == ^node_id and ce.status == "sent",
      order_by: [asc: ce.inserted_at],
      preload: :command
    )
    |> Repo.all()
    |> Enum.map(&CommandExecution.populate_command_text/1)
  end

  @doc """
  Updates command execution result from agent.

  Validates:
  - Execution belongs to the specified node
  - Execution is in "sent" status

  Returns:
  - {:ok, execution} on success
  - {:error, :forbidden} if execution doesn't belong to node
  - {:error, :invalid_status} if execution is not in "sent" status
  - {:error, changeset} on validation errors
  """
  def update_command_execution_result(execution_id, node_id, params) do
    execution = get_command_execution!(execution_id)

    # Verify it belongs to this node
    if execution.node_id != node_id do
      {:error, :forbidden}
    else
      # Only allow updating from "sent" status
      if execution.status != "sent" do
        {:error, :invalid_status}
      else
        # Extract command_execution params from Phoenix-wrapped request
        attrs = params["command_execution"] || %{}

        # Parse completed_at from agent (ISO8601 string to DateTime)
        completed_at =
          case attrs["completed_at"] do
            nil ->
              DateTime.utc_now() |> DateTime.truncate(:second)

            timestamp when is_binary(timestamp) ->
              case DateTime.from_iso8601(timestamp) do
                {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
                _ -> DateTime.utc_now() |> DateTime.truncate(:second)
              end

            %DateTime{} = dt ->
              DateTime.truncate(dt, :second)
          end

        # Build update attrs with agent's completion timestamp
        update_attrs = %{
          status: attrs["status"],
          output: attrs["output"],
          exit_code: attrs["exit_code"],
          completed_at: completed_at
        }

        update_command_execution(execution, update_attrs)
      end
    end
  end
end
