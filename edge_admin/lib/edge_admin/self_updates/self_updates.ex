# edge_admin/lib/edge_admin/self_updates/self_updates.ex
defmodule EdgeAdmin.SelfUpdates do
  @moduledoc """
  The SelfUpdates context handles self-update requests for edge agents.

  This module provides functionality for triggering agent self-updates via their
  self-update service (e.g., Watchtower). Updates are triggered asynchronously
  with status tracking.

  ## Examples

      # Create a self-update request for all nodes
      iex> create_self_update_request(%{
      ...>   "targeting" => %{"type" => "all"}
      ...> })
      {:ok, %SelfUpdateRequest{}}

      # Create a request for specific nodes
      iex> create_self_update_request(%{
      ...>   "targeting" => %{
      ...>     "type" => "nodes",
      ...>     "node_ids" => ["abc-123", "def-456"]
      ...>   }
      ...> })
      {:ok, %SelfUpdateRequest{}}

      # Get a request
      iex> get_self_update_request(request_id)
      {:ok, %SelfUpdateRequest{}}
  """

  import Ecto.Query, warn: false

  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.EdgeClusters.Gateway
  alias EdgeAdmin.Events
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Targeting
  alias EdgeAdmin.Repo
  alias EdgeAdmin.SelfUpdates.Checks
  alias EdgeAdmin.SelfUpdates.Forms
  alias EdgeAdmin.SelfUpdates.Schemas.SelfUpdateRequest
  alias EdgeAdmin.SelfUpdates.Workers.TriggerSelfUpdateWorker

  require Logger

  @doc """
  Gets a single self-update request by ID.

  ## Parameters
  - `id` - The request's UUID

  ## Returns
  - `{:ok, request}` - Request found
  - `{:error, :not_found}` - Request doesn't exist or invalid UUID
  """
  @spec get_self_update_request(String.t()) :: {:ok, SelfUpdateRequest.t()} | {:error, :not_found}
  def get_self_update_request(id) do
    case Repo.get(SelfUpdateRequest, id) do
      nil -> {:error, :not_found}
      request -> {:ok, request}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  @doc """
  Creates a new self-update request and enqueues trigger job.

  Takes targeting specification and creates the request record, then enqueues
  a background job to trigger self-updates for the targeted nodes.

  ## Parameters
  - `attrs` - Map containing:
    - `targeting` - Targeting specification (same format as commands)

  ## Returns
  - `{:ok, request}` - Request created successfully
  - `{:error, changeset}` - Validation failed
  """
  @spec create_self_update_request(map()) :: {:ok, SelfUpdateRequest.t()} | {:error, Ecto.Changeset.t()}
  def create_self_update_request(attrs \\ %{}) do
    with {:ok, validated_attrs} <- Forms.CreateSelfUpdateRequestForm.changeset(attrs),
         changeset = SelfUpdateRequest.changeset(%SelfUpdateRequest{}, validated_attrs),
         {:ok, request} <- Repo.insert(changeset) do
      enqueue_trigger_worker(request)
      {:ok, request}
    end
  end

  @doc """
  Updates a self-update request.

  ## Parameters
  - `request` - The request struct to update
  - `attrs` - Map of attributes to update

  ## Returns
  - `{:ok, request}` - Update succeeded
  - `{:error, changeset}` - Validation failed
  """
  @spec update_self_update_request(SelfUpdateRequest.t(), map()) ::
          {:ok, SelfUpdateRequest.t()} | {:error, Ecto.Changeset.t()}
  def update_self_update_request(%SelfUpdateRequest{} = request, attrs) do
    request
    |> SelfUpdateRequest.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists self-update requests with filtering, sorting, and pagination.

  Supports filtering by:
  - `status` - Enum: `"pending"`, `"processing"`, `"completed"`
  - `inserted_at__gte/lte` - Date range filter
  - `updated_at__gte/lte` - Date range filter

  ## Returns
  - `{:ok, {requests, meta}}` - List of requests with Flop.Meta pagination info
  - `{:error, meta}` - Validation errors
  """
  @spec list_self_update_requests(map()) ::
          {:ok, {[SelfUpdateRequest.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_self_update_requests(params \\ %{}) do
    # Parse params into Flop format
    flop_params = EdgeAdmin.RequestParser.parse(params)

    # Run Flop query
    case Flop.validate_and_run(SelfUpdateRequest, flop_params,
           for: SelfUpdateRequest,
           replace_invalid_params: true
         ) do
      {:ok, {requests, meta}} ->
        {:ok, {requests, meta}}

      {:error, meta} ->
        {:error, meta}
    end
  end

  @doc """
  Checks if the latest self-update request includes the given node.

  This is used by the HTTP fallback mechanism for agents to poll for self-updates
  when VPN connectivity is unavailable.

  ## Parameters
  - `node` - The node struct to check

  ## Returns
  - `{:ok, %{including_me: boolean, inserted_at: DateTime.t() | nil}}`

  ## Behavior
  - If no self-update requests exist: `{:ok, %{including_me: false, inserted_at: nil}}`
  - If latest request doesn't match node: `{:ok, %{including_me: false, inserted_at: datetime}}`
  - If latest request matches node: `{:ok, %{including_me: true, inserted_at: datetime}}`

  ## Examples

      iex> check_for_latest_request(node)
      {:ok, %{including_me: true, inserted_at: ~U[2026-01-29 10:30:45Z]}}

      iex> check_for_latest_request(node)
      {:ok, %{including_me: false, inserted_at: nil}}
  """
  @spec check_for_latest_request(Node.t()) ::
          {:ok, %{including_me: boolean(), inserted_at: DateTime.t() | nil}}
  def check_for_latest_request(%Node{} = node) do
    # Get the absolute latest self-update request by inserted_at (no status filter)
    latest_request =
      SelfUpdateRequest
      |> order_by([r], desc: r.inserted_at)
      |> limit(1)
      |> Repo.one()

    case latest_request do
      nil ->
        # No self-update requests exist
        {:ok, %{including_me: false, inserted_at: nil}}

      request ->
        # Check if node matches this request's targeting filters
        nodes = resolve_targeting_and_filter(request.targeting)
        including_me = Enum.any?(nodes, fn n -> n.id == node.id end)

        {:ok, %{including_me: including_me, inserted_at: request.inserted_at}}
    end
  end

  @doc """
  Deletes a self-update request.

  Validates that the request is completed before deletion.

  ## Parameters
  - `request` - The request struct to delete

  ## Returns
  - `{:ok, request}` - Deletion succeeded
  - `{:error, {:conflict, reason}}` - Request is not completed
  """
  @spec delete_self_update_request(SelfUpdateRequest.t()) ::
          {:ok, SelfUpdateRequest.t()} | {:error, {:conflict, String.t()}}
  def delete_self_update_request(%SelfUpdateRequest{} = request) do
    with :ok <- Checks.RequestCompletedCheck.check(request) do
      Repo.delete(request)
    end
  end

  @doc """
  Processes a self-update request by triggering updates for targeted nodes.

  This is called by the TriggerSelfUpdateWorker. Resolves targeting, filters nodes,
  groups by cluster, and triggers updates via Gateway.

  ## Parameters
  - `request_id` - The request ID to process

  ## Returns

  Always `:ok` — meaning "processing completed", NOT "all triggers succeeded".
  Per-node outcomes (gateway-not-found, self-update disabled, agent error) are
  aggregated into the request's `summary` map (`%{total, triggered, failed}`)
  and the request's `status` transitions to `:completed` regardless of how
  many individual nodes failed. Inspect `summary.failed` to detect partial
  failures.
  """
  @spec process_self_update_request(String.t()) :: :ok
  def process_self_update_request(request_id) do
    {:ok, request} = get_self_update_request(request_id)

    # Update status to processing
    {:ok, request} = update_self_update_request(request, %{status: :processing})

    # Resolve targeting and filter nodes
    nodes = resolve_targeting_and_filter(request.targeting)
    targeting_type = request.targeting["type"]

    if Enum.empty?(nodes) do
      Logger.info("No matching nodes found for self-update request #{request_id}")

      {:ok, completed_request} =
        update_self_update_request(request, %{
          status: :completed,
          summary: %{total: 0, triggered: 0, failed: 0}
        })

      :telemetry.execute(
        [:edge_admin, :self_updates, :request_completed],
        %{total: 0, triggered: 0, failed: 0},
        %{targeting_type: targeting_type}
      )

      Events.publish(%Catalog.SelfUpdateCompleted{request: completed_request})
      :ok
    else
      Logger.info("Triggering self-update for #{length(nodes)} nodes (targeting type: #{targeting_type})")

      # Trigger updates based on targeting type
      results =
        case targeting_type do
          "nodes" ->
            # For "nodes" targeting: lookup each node individually via Metadata
            trigger_updates_for_nodes(nodes, request_id)

          _ ->
            # For "all" and "clusters": group by cluster and use cluster info
            trigger_updates_for_clusters(nodes, request_id)
        end

      # Aggregate results
      triggered_count = Enum.count(results, fn result -> result == :ok end)
      failed_count = length(results) - triggered_count

      summary = %{
        total: length(nodes),
        triggered: triggered_count,
        failed: failed_count
      }

      # Update request with summary
      {:ok, completed_request} =
        update_self_update_request(request, %{
          status: :completed,
          summary: summary
        })

      Logger.info("Self-update request #{request_id} completed: #{inspect(summary)}")
      Events.publish(%Catalog.SelfUpdateCompleted{request: completed_request})

      :telemetry.execute(
        [:edge_admin, :self_updates, :request_completed],
        %{total: summary.total, triggered: summary.triggered, failed: summary.failed},
        %{targeting_type: targeting_type}
      )

      :ok
    end
  end

  # Private Functions

  defp enqueue_trigger_worker(request) do
    %{request_id: request.id}
    |> TriggerSelfUpdateWorker.new()
    |> Oban.insert()

    Logger.info("Enqueued self-update trigger worker for request #{request.id}")
  end

  # Resolve targeting specification and filter nodes
  defp resolve_targeting_and_filter(targeting) do
    targeting_type = targeting["type"]
    node_filters = Map.get(targeting, "node_filters", %{})
    cluster_filters = Map.get(targeting, "cluster_filters", %{})

    # Add required filters: healthy + self_update_enabled
    node_filters =
      node_filters
      |> Map.put("status", "healthy")
      |> Map.put("self_update_enabled", "true")

    case targeting_type do
      "all" ->
        Targeting.nodes_for_all(node_filters, cluster_filters)

      "nodes" ->
        node_ids = Map.get(targeting, "node_ids", [])
        Targeting.nodes_for_ids(node_ids, node_filters)

      "clusters" ->
        cluster_names = Map.get(targeting, "cluster_names", [])
        {nodes, _cluster_id} = Targeting.nodes_for_clusters(cluster_names, node_filters, cluster_filters)
        nodes

      _ ->
        Logger.error("Invalid targeting type: #{targeting_type}")
        []
    end
  end

  # Trigger updates for "nodes" targeting - lookup each node individually via Metadata
  defp trigger_updates_for_nodes(nodes, request_id) do
    tasks =
      Enum.map(nodes, fn node ->
        Task.async(fn ->
          # Build node name and lookup cluster via ETS metadata
          node_name = Node.node_name(node)

          with {:ok, cluster_name, _admin_name} <- Metadata.find_node_cluster(node_name),
               {:ok, gateway_pid} <- Gateway.lookup(cluster_name),
               :ok <- Gateway.trigger_self_update(gateway_pid, node) do
            Logger.info("Triggered self-update for node #{node_name}")
            Events.publish(%Catalog.NodeUpdateTriggered{node: node, self_update_request_id: request_id})
            :ok
          else
            {:error, :self_update_disabled} ->
              Logger.warning("Self-update disabled for node #{node_name}")
              {:error, :disabled}

            {:error, :gateway_not_found} ->
              Logger.error("Gateway not found for node #{node_name}")
              {:error, :gateway_not_found}

            {:error, :no_owner} ->
              Logger.error("No owner found for node #{node_name}")
              {:error, :no_owner}

            {:error, reason} ->
              Logger.error("Failed to trigger self-update for node #{node_name}: #{inspect(reason)}")
              {:error, reason}
          end
        end)
      end)

    # Wait for all tasks to complete
    Task.await_many(tasks, 30_000)
  end

  # Trigger updates for "all" and "clusters" targeting - use cluster.network_name directly
  defp trigger_updates_for_clusters(nodes, request_id) do
    # Group nodes by cluster
    nodes_by_cluster = Enum.group_by(nodes, & &1.cluster)

    Logger.info("Triggering updates across #{map_size(nodes_by_cluster)} clusters")

    # Trigger updates for each cluster (parallel within cluster)
    Enum.flat_map(nodes_by_cluster, fn {cluster, cluster_nodes} ->
      # Use cluster.network_name to lookup gateway (has "cluster-" prefix)
      cluster_name = EdgeAdmin.Nodes.Schemas.Cluster.network_name(cluster)

      case Gateway.lookup(cluster_name) do
        {:ok, gateway_pid} ->
          # Trigger updates in parallel for all nodes in this cluster
          tasks =
            Enum.map(cluster_nodes, fn node ->
              Task.async(fn ->
                case Gateway.trigger_self_update(gateway_pid, node) do
                  :ok ->
                    Logger.info("Triggered self-update for node #{Node.node_name(node)}")
                    Events.publish(%Catalog.NodeUpdateTriggered{node: node, self_update_request_id: request_id})
                    :ok

                  {:error, :self_update_disabled} ->
                    Logger.warning("Self-update disabled for node #{Node.node_name(node)}")
                    {:error, :disabled}

                  {:error, reason} ->
                    Logger.error("Failed to trigger self-update for node #{Node.node_name(node)}: #{inspect(reason)}")
                    {:error, reason}
                end
              end)
            end)

          # Wait for all tasks to complete
          Task.await_many(tasks, 30_000)

        {:error, reason} ->
          Logger.error("Failed to lookup gateway for cluster #{cluster_name}: #{inspect(reason)}")
          # Return errors for all nodes in this cluster
          Enum.map(cluster_nodes, fn _ -> {:error, :gateway_not_found} end)
      end
    end)
  end
end
