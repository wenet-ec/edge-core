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
  alias EdgeAdmin.Commands.Forms
  alias EdgeAdmin.Commands.Workers.ExecutionCreationWorker
  alias EdgeAdmin.FilteringPagination
  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.EdgeClusters.Gateway
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Vpn

  require Logger

  def get_command(id) do
    case Repo.get(Command, id) do
      nil -> {:error, :not_found}
      command -> {:ok, command}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

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

  def get_command_execution(id) do
    case Repo.get(CommandExecution, id) do
      nil -> {:error, :not_found}
      command_execution -> {:ok, Repo.preload(command_execution, [:command, :cluster])}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
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
    FilteringPagination.paginate(
      CommandExecution,
      params,
      filterable_fields: [:status, :target_all, :exit_code, :command_id, :node_id, :output],
      sortable_fields: [:inserted_at, :updated_at, :status, :sent_at, :completed_at, :exit_code],
      default_sort: "inserted_at:desc",
      repo: Repo,
      preload: [:command, :cluster]
    )
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
  - All executions created with status "pending"
  - Uses bulk insert for efficiency
  - Returns {:ok, executions} or {:error, reason}
  """
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
              {get_all_filtered_nodes(node_filters, cluster_filters), nil}

            "nodes" ->
              node_ids = args["node_ids"] || []
              {get_nodes_for_targeting(node_ids, node_filters), nil}

            "clusters" ->
              cluster_names = args["cluster_names"] || []
              get_nodes_for_clusters(cluster_names, node_filters, cluster_filters)

            _ ->
              Logger.error("Invalid targeting type: #{targeting_type}")
              {[], nil}
          end

        if Enum.empty?(nodes) do
          Logger.info("No matching nodes found for command #{command_id}")
          {:ok, []}
        else
          bulk_create_executions(command, nodes, targeting_type == "all", cluster_id)
        end

      {:error, :not_found} ->
        Logger.error("Command not found: #{command_id}")
        {:error, "Command not found"}
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
      # No additional filters, return all nodes
      nodes
    else
      # Apply custom filters (no cluster filters for node targeting)
      all_matching_nodes = get_all_filtered_nodes(node_filters, %{})
      matching_node_ids = MapSet.new(all_matching_nodes, & &1.id)

      Enum.filter(nodes, fn node ->
        MapSet.member?(matching_node_ids, node.id)
      end)
    end
  end

  defp bulk_create_executions(command, nodes, target_all, cluster_id) do
    Logger.info("Creating executions for #{length(nodes)} node(s)")

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    executions =
      Enum.map(nodes, fn node ->
        %{
          command_id: command.id,
          node_id: node.id,
          cluster_id: cluster_id,
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

      {:ok, inserted_executions}
    rescue
      exception ->
        Logger.error("Failed to bulk insert executions: #{Exception.message(exception)}")
        {:error, Exception.message(exception)}
    end
  end

  # Get all cluster names matching cluster_filters
  defp get_all_filtered_cluster_names(cluster_filters, page \\ 1, accumulated_names \\ []) do
    params =
      cluster_filters
      |> Map.put("page_size", "1000")
      |> Map.put("page", to_string(page))

    page_result = Nodes.list_clusters_with_filtering_pagination(params)

    all_names = accumulated_names ++ Enum.map(page_result.data, & &1.name)

    if page_result.has_next do
      get_all_filtered_cluster_names(cluster_filters, page + 1, all_names)
    else
      all_names
    end
  end

  # Get nodes for clusters targeting
  defp get_nodes_for_clusters(cluster_names, node_filters, cluster_filters) do
    # Deduplicate cluster names
    unique_cluster_names = Enum.uniq(cluster_names)

    # Get existing clusters by name (ignore non-existent)
    clusters =
      unique_cluster_names
      |> Enum.map(&Nodes.get_cluster/1)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(clusters) do
      Logger.warning("No valid clusters found from names: #{inspect(unique_cluster_names)}")
      {[], nil}
    else
      # Apply cluster_filters (AND logic with cluster_names)
      filtered_clusters =
        if map_size(cluster_filters) > 0 do
          filtered_cluster_names = get_all_filtered_cluster_names(cluster_filters)
          filtered_set = MapSet.new(filtered_cluster_names)

          Enum.filter(clusters, fn cluster ->
            MapSet.member?(filtered_set, cluster.name)
          end)
        else
          clusters
        end

      if Enum.empty?(filtered_clusters) do
        Logger.info("No clusters match the combined cluster_names AND cluster_filters")
        {[], nil}
      else
        # For single cluster, set cluster_id; for multiple clusters, cluster_id is nil
        cluster_id =
          case filtered_clusters do
            [single_cluster] -> single_cluster.id
            _ -> nil
          end

        # Get all cluster names from filtered clusters
        cluster_names_list = Enum.map(filtered_clusters, & &1.name)

        # Fetch nodes from these clusters with node_filters
        nodes = get_nodes_from_cluster_list(cluster_names_list, node_filters)

        {nodes, cluster_id}
      end
    end
  end

  # Get all nodes from a list of cluster names with node filters
  defp get_nodes_from_cluster_list(
         cluster_names,
         node_filters,
         page \\ 1,
         accumulated_nodes \\ []
       ) do
    cluster_name_set = MapSet.new(cluster_names)

    params =
      node_filters
      |> Map.put("page_size", "1000")
      |> Map.put("page", to_string(page))

    page_result = Nodes.list_nodes_with_filtering_pagination(params)

    # Filter nodes by cluster names
    filtered_nodes =
      Enum.filter(page_result.data, fn node ->
        MapSet.member?(cluster_name_set, node.cluster.name)
      end)

    all_nodes = accumulated_nodes ++ filtered_nodes

    if page_result.has_next do
      get_nodes_from_cluster_list(cluster_names, node_filters, page + 1, all_nodes)
    else
      all_nodes
    end
  end

  # Helper function to get all nodes across all pages
  defp get_all_filtered_nodes(node_filters, cluster_filters, page \\ 1, accumulated_nodes \\ []) do
    # First get filtered clusters if cluster_filters provided
    cluster_names =
      if map_size(cluster_filters) > 0 do
        get_all_filtered_cluster_names(cluster_filters)
      else
        nil
      end

    params =
      node_filters
      |> Map.put("page_size", "100")
      |> Map.put("page", to_string(page))

    # Add cluster_name filter if we have filtered clusters
    params =
      if cluster_names do
        # Note: list_nodes supports cluster_name filter (singular) for join-based filtering
        # We need to query each cluster separately or modify the query
        # For now, we'll fetch all and filter in memory
        params
      else
        params
      end

    page_result = Nodes.list_nodes_with_filtering_pagination(params)

    # Filter by cluster names if provided
    filtered_nodes =
      if cluster_names do
        cluster_name_set = MapSet.new(cluster_names)

        Enum.filter(page_result.data, fn node ->
          MapSet.member?(cluster_name_set, node.cluster.name)
        end)
      else
        page_result.data
      end

    all_nodes = accumulated_nodes ++ filtered_nodes

    if page_result.has_next do
      get_all_filtered_nodes(node_filters, cluster_filters, page + 1, all_nodes)
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

    Logger.debug(
      "Execution delivery - my_cluster_network_names: #{inspect(my_cluster_network_names)}"
    )

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
          fn {_node_id, executions} ->
            deliver_to_single_node(executions)
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
  end

  defp deliver_to_single_node(executions) do
    # Get the node (already preloaded from query)
    node = hd(executions).node

    # Lookup local gateway for this cluster
    case lookup_gateway(node) do
      {:ok, gateway_pid} ->
        deliver_executions_via_gateway(gateway_pid, node, executions)

      {:error, :gateway_not_found} ->
        Logger.debug("Gateway not found for cluster #{node.cluster.name}, will retry later")
        :skip
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
    # Deliver all executions at once - don't stop on failures
    Logger.info("Delivering #{length(executions)} executions to node #{node.id}")

    Enum.each(executions, fn execution ->
      execution_data = %{
        id: execution.id,
        command_id: execution.command_id,
        node_id: execution.node_id,
        command_text: CommandExecution.command_text(execution),
        timeout: CommandExecution.timeout(execution),
        status: "pending"
      }

      case Gateway.create_command_execution(gateway_pid, node, execution_data) do
        {:ok, :sent} ->
          # Agent received it - update to "sent"
          update_command_execution(execution, %{
            status: "sent",
            sent_at: DateTime.utc_now()
          })

        {:error, reason} ->
          Logger.warning(
            "Failed to deliver execution #{execution.id} to node #{node.id}: #{inspect(reason)}"
          )
      end
    end)

    :ok
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
  def verify_execution_belongs_to_node(execution, node_id) do
    if execution.node_id == node_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  def update_command_execution_result(execution, params) do
    with {:ok, attrs} <- Forms.UpdateCommandExecutionResultForm.changeset(params, execution.status) do
      # Hardcode status to "completed" since form validated current status is "sent"
      attrs = Map.put(attrs, "status", "completed")
      update_command_execution(execution, attrs)
    end
  end
end
