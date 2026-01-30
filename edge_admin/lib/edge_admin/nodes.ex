# edge_admin/lib/edge_admin/nodes.ex
defmodule EdgeAdmin.Nodes do
  @moduledoc """
  The Nodes context handles edge agent node management.

  Nodes represent edge devices (agents) enrolled in the system. Each node belongs
  to a cluster and can execute commands via SSH or proxy connections.

  ## Key Concepts

  - **Node**: An enrolled edge device running the EdgeAgent, identified by a UUID
  - **Cluster**: A logical grouping of nodes in an isolated VPN network
  - **Enrollment**: Process of adding a new node to the system via enrollment keys
  - **Alias**: Custom DNS entry for a node (e.g., "web-server" -> "node-abc123")
  - **Health Check**: Periodic pings to verify node availability (healthy/unhealthy/unreachable)

  ## Architecture

  The module uses a **database-first approach** with best-effort Netmaker sync:
  - Database is the source of truth
  - Netmaker (VPN provider) is synced via external calls
  - Background reconciliation workers fix any drift between DB and Netmaker
  - Transactions ensure atomicity of critical operations (create/delete)

  ## Examples

      # List all nodes with filtering and pagination
      iex> list_nodes(%{"cluster_name" => "prod", "status" => "healthy"})
      {:ok, {[%Node{}, ...], %Flop.Meta{}}}

      # Get a single node by ID
      iex> get_node("abc-123")
      {:ok, %Node{id: "abc-123", cluster: %Cluster{}, ...}}

      # Register or update a node from agent
      iex> register_node(%{"node_id" => "abc-123", "network_name" => "cluster-default", ...})
      {:ok, %Node{}}

      # Create a cluster
      iex> create_cluster(%{"name" => "prod", "ipv4_range" => "100.64.1.0/24"})
      {:ok, %Cluster{}}

      # Create an alias for a node
      iex> create_alias(node, %{"name" => "web-server"})
      {:ok, %Alias{}}
  """

  import Ecto.Query, warn: false

  alias Ecto.Query.CastError
  alias EdgeAdmin.Nodes.Forms
  alias EdgeAdmin.Nodes.Rules.DeletionRules
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo
  alias EdgeAdmin.RequestParser
  alias EdgeAdmin.Vpn

  require Logger

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # Broadcasts metadata recomputation event to all admins in this admin cluster
  defp broadcast_metadata_event(event) do
    Phoenix.PubSub.broadcast(
      EdgeAdmin.PubSub,
      "#{Vpn.admin_cluster_name()}:metadata",
      event
    )
  end

  # Builds network name for a cluster (node network, not admin network)
  defp node_network_name(%Cluster{name: name}), do: Vpn.build_network_name(name, prefix: :node)

  defp node_network_name(cluster_name) when is_binary(cluster_name),
    do: Vpn.build_network_name(cluster_name, prefix: :node)

  # ===========================================================================
  # Cluster functions
  # ===========================================================================

  @doc """
  Lists all clusters with node counts, filtering, and pagination.

  Supports filtering by:
  - `name` - Text search (supports wildcards: `prod*`, `*tion`, `*rod*`)
  - `ipv4_range` - Text search (supports wildcards)
  - `inserted_at` - Range queries (e.g., `inserted_at__gte=2025-01-01`, `inserted_at__lte=2025-12-31`)
  - `node_count` - Range queries (e.g., `node_count__gte=5`, `node_count__lte=10`)

  Supports sorting by:
  - `name`, `ipv4_range`, `inserted_at`, `updated_at`
  - Default: `inserted_at:desc`

  ## Parameters
  - `params` - Map of filter/sort/pagination parameters (Flop format)

  ## Returns
  - `{:ok, {clusters, meta}}` - List of clusters with pagination metadata
  - `{:error, meta}` - Validation errors

  ## Examples

      iex> list_clusters(%{"name__ilike" => "prod*"})
      {:ok, {[%Cluster{name: "production"}], %Flop.Meta{}}}

      iex> list_clusters(%{"node_count__gte" => "5"})
      {:ok, {[%Cluster{nodes: [...]}, ...], %Flop.Meta{}}}
  """
  @spec list_clusters(map()) :: {:ok, {[Cluster.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_clusters(params \\ %{}) do
    # Parse API params into Flop format
    flop_params = RequestParser.parse(params)

    # Extract node_count filters to handle separately (computed field)
    {node_count_filters, other_filters} =
      Enum.split_with(flop_params[:filters] || [], fn filter ->
        filter.field == :node_count
      end)

    # Build base query with node_count if filtering/sorting on it
    base_query =
      if node_count_filters == [] do
        Cluster
      else
        apply_node_count_filters(
          from(c in Cluster,
            left_join: n in assoc(c, :nodes),
            group_by: c.id,
            select_merge: %{node_count: count(n.id)}
          ),
          node_count_filters
        )
      end

    flop_params = Map.put(flop_params, :filters, other_filters)

    case Flop.validate_and_run(base_query, flop_params,
           for: Cluster,
           replace_invalid_params: true
         ) do
      {:ok, {clusters, meta}} ->
        # Preload nodes to compute node_count for response
        clusters_with_nodes = Repo.preload(clusters, :nodes)
        {:ok, {clusters_with_nodes, meta}}

      {:error, meta} ->
        {:error, meta}
    end
  end

  # Apply node_count filters using HAVING clause
  defp apply_node_count_filters(query, filters) do
    Enum.reduce(filters, query, fn filter, acc_query ->
      apply_node_count_filter(acc_query, filter)
    end)
  end

  defp apply_node_count_filter(query, %{op: :>=, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) >= ^num)
      _ -> query
    end
  end

  defp apply_node_count_filter(query, %{op: :>, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) > ^num)
      _ -> query
    end
  end

  defp apply_node_count_filter(query, %{op: :<=, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) <= ^num)
      _ -> query
    end
  end

  defp apply_node_count_filter(query, %{op: :<, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) < ^num)
      _ -> query
    end
  end

  defp apply_node_count_filter(query, %{op: :==, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) == ^num)
      _ -> query
    end
  end

  defp apply_node_count_filter(query, %{op: :!=, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) != ^num)
      _ -> query
    end
  end

  defp apply_node_count_filter(query, _), do: query

  @doc """
  Lists cluster-node mappings.

  ## Options
  - `:prefix` - Add DNS name prefixes (default: false)
    - `true`: Returns "cluster-prod", "node-abc123" (for metadata)
    - `false`: Returns "prod", "abc123" (for discovery endpoints)
  - `:filter_status` - Filter nodes by status (default: nil, includes all)
    - Example: `["healthy", "unhealthy"]` excludes unreachable nodes

  ## Returns
  List of maps:
  ```
  # With prefix: true
  [
    %{name: "cluster-prod-east", nodes: ["node-abc123", "node-def456"]},
    %{name: "cluster-staging", nodes: ["node-xyz789"]}
  ]

  # With prefix: false
  [
    %{name: "prod-east", nodes: ["abc123", "def456"]},
    %{name: "staging", nodes: ["xyz789"]}
  ]
  ```
  """
  @spec list_cluster_node_mappings(keyword()) :: [map()]
  def list_cluster_node_mappings(opts \\ []) do
    use_prefix = Keyword.get(opts, :prefix, false)
    filter_status = Keyword.get(opts, :filter_status)

    base_query =
      from(c in Cluster,
        left_join: n in assoc(c, :nodes),
        select: %{
          cluster_name: c.name,
          node_id: n.id
        },
        order_by: [asc: c.inserted_at]
      )

    # Apply status filter if provided
    query =
      if filter_status do
        from([c, n] in base_query,
          where: is_nil(n.id) or n.status in ^filter_status
        )
      else
        base_query
      end

    query
    |> Repo.all()
    |> Enum.group_by(
      fn row -> row.cluster_name end,
      fn row ->
        case row.node_id do
          nil -> nil
          id -> if use_prefix, do: Vpn.build_dns_name(id, prefix: :node), else: id
        end
      end
    )
    |> Enum.map(fn {cluster_name, node_ids} ->
      %{
        name: if(use_prefix, do: node_network_name(cluster_name), else: cluster_name),
        nodes: Enum.reject(node_ids, &is_nil/1)
      }
    end)
  end

  @doc """
  Gets a single cluster by name.

  ## Parameters
  - `name` - The cluster name

  ## Returns
  - `{:ok, cluster}` - Cluster found (with nodes preloaded)
  - `{:error, :not_found}` - Cluster doesn't exist

  ## Examples

      iex> get_cluster("production")
      {:ok, %Cluster{name: "production", nodes: [...]}}

      iex> get_cluster("nonexistent")
      {:error, :not_found}
  """
  @spec get_cluster(String.t()) :: {:ok, Cluster.t()} | {:error, :not_found}
  def get_cluster(name) do
    case Repo.get_by(Cluster, name: name) do
      nil -> {:error, :not_found}
      cluster -> {:ok, Repo.preload(cluster, :nodes)}
    end
  end

  @doc """
  Creates a cluster and its Netmaker network.

  Flow:
  1. Check Netmaker health (fail fast if service unavailable)
  2. Validate input and generate IP range if needed
  3. Create DB record FIRST (validates uniqueness constraints)
  4. Create Netmaker network (rollback DB on failure)
  5. Emit event for metadata recomputation

  If health check fails, returns service unavailable immediately (no DB call).
  If DB creation fails, returns validation error immediately (no Netmaker call).
  If Netmaker creation fails, deletes DB record and returns service unavailable.

  This ensures "cluster in DB but network not in Netmaker" always means failed deletion,
  allowing reconciliation to safely delete orphaned DB clusters.

  Returns `{:ok, cluster}`, `{:error, changeset}` (validation), or `{:error, :service_unavailable}` (health check or Netmaker failure).
  """
  @spec create_cluster(map()) :: {:ok, Cluster.t()} | {:error, Ecto.Changeset.t()} | {:error, :service_unavailable}
  def create_cluster(attrs \\ %{}) do
    with {:ok, validated_attrs} <- Forms.CreateClusterForm.changeset(attrs),
         # Check Netmaker health before proceeding
         :ok <- Vpn.health_check(),
         existing_ranges = Repo.all(from(c in Cluster, select: c.ipv4_range)),
         ipv4_range = validated_attrs["ipv4_range"] || Vpn.generate_next_subnet(existing_ranges),
         cluster_attrs = Map.put(validated_attrs, "ipv4_range", ipv4_range),
         {:ok, cluster} <- %Cluster{} |> Cluster.changeset(cluster_attrs) |> Repo.insert() do
      # DB insert succeeded - now create Netmaker network
      network_name = node_network_name(cluster)

      case Vpn.create_network(network_name, %{addressrange: ipv4_range}) do
        {:ok, _} ->
          Logger.info("Created Netmaker network: #{network_name}")
          broadcast_metadata_event({:cluster_created, cluster.id})
          {:ok, cluster}

        {:error, :service_unavailable} = error ->
          # Netmaker failed - rollback DB insert
          Logger.warning("Netmaker network creation failed, rolling back DB cluster: #{cluster.name}")
          Repo.delete(cluster)
          error
      end
    end
  end

  @doc """
  Updates a cluster.

  ## Parameters
  - `cluster` - The cluster struct to update
  - `attrs` - Map of attributes to update

  ## Returns
  - `{:ok, cluster}` - Update succeeded
  - `{:error, changeset}` - Validation failed

  ## Examples

      iex> update_cluster(cluster, %{"name" => "new-name"})
      {:ok, %Cluster{name: "new-name"}}
  """
  @spec update_cluster(Cluster.t(), map()) :: {:ok, Cluster.t()} | {:error, Ecto.Changeset.t()}
  def update_cluster(%Cluster{} = cluster, attrs) do
    cluster
    |> Cluster.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a cluster and its Netmaker network.
  Fails if cluster has nodes.

  Flow (Netmaker-first):
  1. Verify cluster is empty (deletion rule)
  2. Delete network from Netmaker FIRST
  3. Delete from DB
  4. Emit event for metadata recomputation

  If Netmaker deletion fails (except :not_found), operation stops and returns error.
  If Netmaker returns :not_found, continues with DB deletion (network already gone).

  This ensures "cluster in DB but network not in Netmaker" always means failed deletion,
  allowing reconciliation to safely delete orphaned DB clusters.

  Returns `{:ok, cluster}`, `{:error, changeset}` (validation/DB failure), or `{:error, :service_unavailable}` (Netmaker failure).
  """
  @spec delete_cluster(Cluster.t()) ::
          {:ok, Cluster.t()} | {:error, Ecto.Changeset.t()} | {:error, :service_unavailable}
  def delete_cluster(%Cluster{} = cluster) do
    case DeletionRules.validate_cluster_deletion(cluster) do
      :ok ->
        network_name = node_network_name(cluster)

        # 1. Delete network from Netmaker FIRST
        case Vpn.delete_network(network_name) do
          {:ok, _} ->
            Logger.info("Deleted network #{network_name} from Netmaker")
            delete_cluster_from_db(cluster)

          {:error, :not_found} ->
            # Network already gone - continue with DB deletion
            Logger.info("Netmaker network #{network_name} already deleted")
            delete_cluster_from_db(cluster)

          {:error, :service_unavailable} = error ->
            # Netmaker failed - stop operation
            Logger.error("Failed to delete Netmaker network #{network_name}, aborting cluster deletion")
            error
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp delete_cluster_from_db(%Cluster{} = cluster) do
    case Repo.delete(cluster) do
      {:ok, deleted_cluster} ->
        broadcast_metadata_event({:cluster_deleted, cluster.id})
        {:ok, deleted_cluster}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Returns a changeset for tracking cluster changes (for forms).

  ## Examples

      iex> change_cluster(cluster)
      %Ecto.Changeset{data: %Cluster{}}
  """
  @spec change_cluster(Cluster.t(), map()) :: Ecto.Changeset.t()
  def change_cluster(%Cluster{} = cluster, attrs \\ %{}) do
    Cluster.changeset(cluster, attrs)
  end

  # ===========================================================================
  # Node functions
  # ===========================================================================

  @doc """
  Builds the HTTP URL for a node.

  ## Parameters
  - `node` - The node struct (must have cluster preloaded)

  ## Returns
  - String URL in format: `http://node-{id}.cluster-{name}.{domain}:{port}`

  ## Examples

      iex> node_http_url(node)
      "http://node-abc123.cluster-prod.nm.internal:8080"
  """
  @spec node_http_url(Node.t()) :: String.t()
  def node_http_url(%Node{http_port: port} = node) do
    "http://#{Node.dns_hostname(node)}:#{port}"
  end

  @doc """
  Gets a single node by ID.

  ## Parameters
  - `id` - The node's UUID

  ## Returns
  - `{:ok, node}` - Node found (with cluster and aliases preloaded)
  - `{:error, :not_found}` - Node doesn't exist or invalid UUID format

  ## Examples

      iex> get_node("abc-123")
      {:ok, %Node{id: "abc-123", cluster: %Cluster{}, aliases: [...]}}

      iex> get_node("invalid")
      {:error, :not_found}
  """
  @spec get_node(String.t()) :: {:ok, Node.t()} | {:error, :not_found}
  def get_node(id) do
    case Repo.get(Node, id) do
      nil -> {:error, :not_found}
      node -> {:ok, Repo.preload(node, [:cluster, aliases: :cluster])}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc """
  Creates a new node.

  ## Parameters
  - `attrs` - Map of node attributes

  ## Returns
  - `{:ok, node}` - Node created successfully
  - `{:error, changeset}` - Validation failed

  ## Examples

      iex> create_node(%{"id" => "abc-123", "cluster_id" => cluster.id, ...})
      {:ok, %Node{id: "abc-123"}}
  """
  @spec create_node(map()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()}
  def create_node(attrs \\ %{}) do
    %Node{}
    |> Node.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a node.

  ## Parameters
  - `node` - The node struct to update
  - `attrs` - Map of attributes to update

  ## Returns
  - `{:ok, node}` - Update succeeded
  - `{:error, changeset}` - Validation failed

  ## Examples

      iex> update_node(node, %{"status" => "unhealthy"})
      {:ok, %Node{status: "unhealthy"}}
  """
  @spec update_node(Node.t(), map()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()}
  def update_node(%Node{} = node, attrs) do
    node
    |> Node.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Changes a node's cluster.

  DB-first approach: Updates database immediately, then best-effort syncs with Netmaker.
  A background reconciliation worker handles any inconsistencies.

  Flow:
  1. Delete all aliases (they're cluster-specific)
  2. Update database (source of truth)
  3. Best-effort sync: Add host to new network
  4. Best-effort sync: Remove host from old network
  5. Emit event for metadata recomputation

  Inconsistencies are handled by the cluster reconciliation worker.

  ## Parameters
  - `node` - The node struct to move
  - `params` - Request params containing new cluster name (validated through ChangeNodeClusterForm)

  ## Returns
  - `{:ok, updated_node}` - Node cluster changed successfully
  - `{:error, changeset}` - Validation failed
  """
  @spec change_node_cluster(Node.t(), map()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()}
  def change_node_cluster(%Node{} = node, params) do
    with {:ok, new_cluster_name} <- Forms.ChangeNodeClusterForm.changeset(params),
         {:ok, new_cluster} <- get_cluster(new_cluster_name) do
      old_cluster_id = node.cluster_id

      # 1. Delete all aliases (they're cluster-specific and DNS entries are in old network)
      cleanup_node_aliases(node)

      # 2. Update database first (source of truth)
      case node
           |> Ecto.Changeset.change(cluster_id: new_cluster.id)
           |> Repo.update() do
        {:ok, updated_node} ->
          updated_node = Repo.preload(updated_node, [:cluster, aliases: :cluster], force: true)

          # 3. Emit PubSub event for metadata recomputation
          broadcast_metadata_event({:node_updated, node.id, old_cluster_id, new_cluster.id})

          # 4. Best-effort Netmaker sync (don't fail if this doesn't work)
          # The reconciliation worker will fix any inconsistencies
          old_network_name = node_network_name(node.cluster)
          new_network_name = node_network_name(new_cluster)

          case Vpn.add_host_to_network(node.netmaker_host_id, new_network_name) do
            {:ok, _} ->
              Logger.info("Added host #{node.netmaker_host_id} to network #{new_network_name}")

              case Vpn.remove_host_from_network(node.netmaker_host_id, old_network_name) do
                {:ok, _} ->
                  Logger.info("Removed host #{node.netmaker_host_id} from network #{old_network_name}")

                {:error, reason} ->
                  Logger.warning(
                    "Failed to remove host #{node.netmaker_host_id} from old network #{old_network_name}: #{inspect(reason)}. " <>
                      "Reconciliation worker will handle cleanup."
                  )
              end

            {:error, reason} ->
              Logger.warning(
                "Failed to add host #{node.netmaker_host_id} to new network #{new_network_name}: #{inspect(reason)}. " <>
                  "Reconciliation worker will handle sync."
              )
          end

          {:ok, updated_node}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc """
  Deletes a node and its Netmaker host.

  Flow (Netmaker-first):
  1. Clean up DNS records (aliases) from Netmaker (best-effort)
  2. Delete host from Netmaker FIRST
  3. Delete from DB (cascades to ssh_usernames, ssh_public_keys, command_executions, aliases)
  4. Emit event for metadata recomputation

  If Netmaker deletion fails (except :not_found), operation stops and returns error.
  If Netmaker returns :not_found, continues with DB deletion (already gone).

  This ensures "node in DB but host not in Netmaker" always means failed deletion,
  allowing reconciliation to safely delete orphaned DB nodes.

  Returns `{:ok, node}`, `{:error, changeset}` (DB failure), or `{:error, :service_unavailable}` (Netmaker failure).
  """
  @spec delete_node(Node.t()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()} | {:error, :service_unavailable}
  def delete_node(%Node{} = node) do
    # 1. Clean up DNS records (aliases) from Netmaker (best-effort, outside main flow)
    cleanup_node_aliases(node)

    # 2. Delete host from Netmaker FIRST
    case Vpn.delete_host(node.netmaker_host_id) do
      {:ok, _} ->
        Logger.info("Deleted host #{node.netmaker_host_id} from Netmaker")
        delete_node_from_db(node)

      {:error, :not_found} ->
        # Host already gone - continue with DB deletion
        Logger.info("Netmaker host #{node.netmaker_host_id} already deleted")
        delete_node_from_db(node)

      {:error, :service_unavailable} = error ->
        # Netmaker failed - stop operation
        Logger.error("Failed to delete Netmaker host #{node.netmaker_host_id}, aborting node deletion")
        error
    end
  end

  defp delete_node_from_db(%Node{} = node) do
    # Delete from DB (cascades to ssh_usernames, ssh_public_keys, command_executions, aliases)
    case Repo.delete(node) do
      {:ok, deleted_node} ->
        broadcast_metadata_event({:node_deleted, node.id, node.cluster_id})
        {:ok, deleted_node}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Returns a changeset for tracking node changes (for forms).

  ## Examples

      iex> change_node(node)
      %Ecto.Changeset{data: %Node{}}
  """
  @spec change_node(Node.t(), map()) :: Ecto.Changeset.t()
  def change_node(%Node{} = node, attrs \\ %{}) do
    Node.changeset(node, attrs)
  end

  @doc """
  Registers or updates a node from agent.

  Verifies cluster and Netmaker node existence, generates new tokens on every registration,
  and creates or updates the node record.

  ## Parameters
  - `params` - Node registration parameters (validated through RegisterNodeForm)

  ## Returns
  - `{:ok, node}` - Node registered/updated successfully
  - `{:error, changeset}` - Validation or registration failed
  """
  @spec register_node(map()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()}
  def register_node(params) do
    with {:ok, attrs} <- Forms.RegisterNodeForm.changeset(params) do
      %{
        "node_id" => node_id,
        "network_name" => network_name
      } = attrs

      # 1. Parse cluster name from network name (e.g., "cluster-default" -> "default")
      cluster_name = String.replace_prefix(network_name, "cluster-", "")

      # 2. Get cluster
      {:ok, cluster} = get_cluster(cluster_name)

      # 3. Verify node exists in Netmaker and get host ID
      node_hostname = Vpn.build_dns_name(node_id, prefix: :node)

      case Vpn.get_host_id(node_hostname, network_name: network_name) do
        {:ok, netmaker_host_id} ->
          # 4. Generate new tokens on every registration
          existing_node = Repo.get(Node, node_id)
          is_new_node = is_nil(existing_node)

          api_token = generate_token()
          proxy_password = generate_token()

          now = DateTime.truncate(DateTime.utc_now(), :second)

          # 5. Create or update node record
          node_attrs = %{
            id: node_id,
            cluster_id: cluster.id,
            netmaker_host_id: netmaker_host_id,
            id_type: attrs["id_type"],
            status: "healthy",
            last_seen_at: now,
            http_port: attrs["http_port"],
            ssh_port: attrs["ssh_port"],
            host_metrics_port: attrs["host_metrics_port"],
            wireguard_metrics_port: attrs["wireguard_metrics_port"],
            http_proxy_port: attrs["http_proxy_port"],
            socks5_proxy_port: attrs["socks5_proxy_port"],
            api_token: api_token,
            proxy_password: proxy_password,
            version: attrs["version"],
            self_update_enabled: attrs["self_update_enabled"],
            relay_enabled: attrs["relay_enabled"]
          }

          result =
            case existing_node do
              nil ->
                # New node - create it
                create_node(node_attrs)

              node ->
                # Existing node - update it
                update_node(node, node_attrs)
            end

          case result do
            {:ok, node} ->
              # Emit event only for new nodes (Metadata will recompute assignments)
              if is_new_node do
                broadcast_metadata_event({:node_created, node_id, cluster.id})
              end

              {:ok, node}

            {:error, changeset} ->
              {:error, changeset}
          end

        {:error, _reason} ->
          Forms.RegisterNodeForm.add_netmaker_not_found_error()
      end
    end
  end

  defp generate_token do
    32 |> :crypto.strong_rand_bytes() |> Base.encode64(padding: false)
  end

  @doc """
  Updates node health status from agent health check report.

  Called when agent reports its health via HTTP fallback mode.
  Updates node status and last_seen_at timestamp.

  ## Parameters
  - `node` - The node struct
  - `params` - Health check parameters (validated through NodeHealthCheckForm)

  ## Returns
  - `{:ok, node}` - Node updated successfully
  - `{:error, changeset}` - Validation or update failed
  """
  @spec update_node_health_check(Node.t(), map()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()}
  def update_node_health_check(node, params) do
    with {:ok, attrs} <- Forms.NodeHealthCheckForm.changeset(params) do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      update_attrs = %{
        status: attrs["status"],
        last_seen_at: now
      }

      update_node(node, update_attrs)
    end
  end

  @doc """
  Performs health check on all nodes assigned to this admin.

  Called by Quantum scheduler periodically. Reads from Metadata ETS to determine
  which nodes this admin governs, then performs parallel health checks.

  Health check logic:
  - 200 response => status: "healthy", update last_seen_at
  - 503 response => status: "unhealthy", update last_seen_at (we reached it)
  - Network error/timeout => status: "unreachable" only if last_seen_at > 5 minutes ago,
    otherwise keep existing status (agent might be reporting via HTTP fallback)

  Logs warnings for unreachable and unhealthy nodes.
  """
  @spec check_node_health() :: :ok
  def check_node_health do
    concurrency = Application.get_env(:edge_admin, :node_health_check_concurrency, 100)
    # Use HTTP agent timeouts for health checks
    timeout = Application.get_env(:edge_admin, :http_agent_receive_timeout)

    # Get nodes this admin governs from ETS
    # Returns %{cluster_name => ["node-{id}", "node-{id2}"]}
    my_clusters = EdgeAdmin.Admins.Metadata.get_my_clusters()
    node_names = my_clusters |> Map.values() |> List.flatten()

    if Enum.empty?(node_names) do
      Logger.debug("No nodes assigned to this admin for health check")
      :ok
    else
      # Extract node IDs from node names (e.g., "node-abc123" => "abc123")
      node_ids =
        Enum.map(node_names, fn node_name ->
          String.replace_prefix(node_name, "node-", "")
        end)

      # Load full node records from DB
      nodes = Repo.all(from(n in Node, where: n.id in ^node_ids, preload: [:cluster]))

      Logger.debug(
        "Starting health check for #{length(nodes)} nodes (concurrency: #{concurrency}, timeout: #{timeout}ms)"
      )

      start_time = System.monotonic_time(:millisecond)

      # Ping all nodes in parallel
      results =
        nodes
        |> Task.async_stream(
          &ping_node(&1, timeout),
          max_concurrency: concurrency,
          timeout: timeout + 500,
          on_timeout: :kill_task
        )
        |> Enum.reduce(%{healthy: 0, unhealthy: 0, unreachable: 0}, fn
          {:ok, :healthy}, acc -> %{acc | healthy: acc.healthy + 1}
          {:ok, :unhealthy}, acc -> %{acc | unhealthy: acc.unhealthy + 1}
          {:ok, :unreachable}, acc -> %{acc | unreachable: acc.unreachable + 1}
          {:exit, _reason}, acc -> %{acc | unreachable: acc.unreachable + 1}
        end)

      elapsed = System.monotonic_time(:millisecond) - start_time

      Logger.info(
        "Health check completed in #{elapsed}ms: " <>
          "#{results.healthy} healthy, #{results.unhealthy} unhealthy, " <>
          "#{results.unreachable} unreachable"
      )

      # Emit summary telemetry
      :telemetry.execute(
        [:edge_admin, :nodes, :health_check_summary],
        %{unhealthy_count: results.unhealthy + results.unreachable, count: 1, total: 1},
        %{}
      )

      :ok
    end
  end

  defp ping_node(node, timeout) do
    url = "#{node_http_url(node)}/health"
    now = DateTime.truncate(DateTime.utc_now(), :second)
    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        case Req.get(url, receive_timeout: timeout, connect_options: [timeout: timeout], retry: false) do
          {:ok, %{status: 200}} ->
            update_node(node, %{status: "healthy", last_seen_at: now})
            :healthy

          {:ok, %{status: 503}} ->
            Logger.warning("Node #{node.id} is unhealthy (503 response)")
            update_node(node, %{status: "unhealthy", last_seen_at: now})
            :unhealthy

          _ ->
            handle_unreachable_node(node)
        end
      catch
        _, _ ->
          handle_unreachable_node(node)
      end

    duration = System.monotonic_time(:millisecond) - start_time

    :telemetry.execute(
      [:edge_admin, :nodes, :health_check],
      %{duration: duration, count: 1, total: 1},
      %{result: result}
    )

    result
  end

  # Only mark as unreachable if last_seen_at is > 5 minutes ago
  # Otherwise keep existing status (agent might be using HTTP fallback to report health)
  defp handle_unreachable_node(node) do
    five_minutes_ago = DateTime.add(DateTime.utc_now(), -5, :minute)

    should_mark_unreachable =
      case node.last_seen_at do
        nil -> true  # Never seen before
        last_seen -> DateTime.compare(last_seen, five_minutes_ago) == :lt
      end

    if should_mark_unreachable do
      Logger.warning("Node #{node.id} is unreachable (no contact for > 5 minutes)")
      update_node(node, %{status: "unreachable"})
      :unreachable
    else
      Logger.debug("Node #{node.id} ping failed but last_seen_at is recent, keeping status: #{node.status}")
      # Keep existing status - might be using HTTP fallback
      String.to_atom(node.status)
    end
  end

  @doc """
  Lists nodes with filtering, sorting, and pagination.

  Supports filtering by:
  - `id_type` - Enum: "persistent" or "random"
  - `status` - Enum: "healthy", "unhealthy", or "unreachable"
  - `version` - Text search with wildcard support (1.0.0 exact, 1.* ilike)
  - `self_update_enabled` - Boolean
  - `last_seen_at__gte/lte` - Datetime range filter
  - `inserted_at__gte/lte` - Date range filter
  - `cluster_name` - Text search with wildcard support (requires join)

  ## Returns
  - `{:ok, {nodes, meta}}` - List of nodes with Flop.Meta pagination info
  - `{:error, meta}` - Validation errors (when replace_invalid_params: false)
  """
  @spec list_nodes(map()) :: {:ok, {[Node.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_nodes(params \\ %{}) do
    # Parse params into Flop format
    flop_params = RequestParser.parse(params)

    # Extract cluster_name filters (join-based, handle separately)
    {cluster_name_filters, other_filters} =
      Enum.split_with(flop_params[:filters] || [], fn filter ->
        filter.field == :cluster_name
      end)

    # Build base query with cluster preload
    base_query =
      from(n in Node,
        join: c in assoc(n, :cluster),
        preload: [:cluster, aliases: :cluster]
      )

    # Apply cluster_name filters if present
    query_with_cluster_filter =
      if cluster_name_filters == [] do
        base_query
      else
        apply_cluster_name_filters(base_query, cluster_name_filters)
      end

    # Remove cluster_name filters from Flop params (handled above)
    flop_params = Map.put(flop_params, :filters, other_filters)

    # Run Flop query
    case Flop.validate_and_run(query_with_cluster_filter, flop_params,
           for: Node,
           replace_invalid_params: true
         ) do
      {:ok, {nodes, meta}} ->
        {:ok, {nodes, meta}}

      {:error, meta} ->
        {:error, meta}
    end
  end

  # Apply cluster_name filters using WHERE clause on joined cluster table
  defp apply_cluster_name_filters(query, filters) do
    Enum.reduce(filters, query, fn filter, acc_query ->
      apply_cluster_name_filter(acc_query, filter)
    end)
  end

  defp apply_cluster_name_filter(query, %{op: :==, value: value}) when is_binary(value) do
    from([_main, c] in query, where: c.name == ^value)
  end

  defp apply_cluster_name_filter(query, %{op: :ilike, value: value}) when is_binary(value) do
    from([_main, c] in query, where: ilike(c.name, ^value))
  end

  defp apply_cluster_name_filter(query, _), do: query

  @doc """
  Gets multiple nodes by their IDs.

  ## Parameters
  - `node_ids` - List of node IDs

  ## Returns
  - List of `{:ok, node}` or `{:error, message}` tuples

  ## Examples

      iex> get_nodes_by_ids(["abc-123", "def-456"])
      [{:ok, %Node{id: "abc-123"}}, {:ok, %Node{id: "def-456"}}]

      iex> get_nodes_by_ids(["abc-123", "invalid"])
      [{:ok, %Node{id: "abc-123"}}, {:error, "Node invalid not found"}]
  """
  @spec get_nodes_by_ids([String.t()]) :: [{:ok, Node.t()} | {:error, String.t()}]
  def get_nodes_by_ids(node_ids) do
    Enum.map(node_ids, fn node_id ->
      case get_node(node_id) do
        {:ok, node} -> {:ok, node}
        {:error, :not_found} -> {:error, "Node #{node_id} not found"}
      end
    end)
  end

  @doc """
  Lists all valid node identifiers (IDs and aliases) for a cluster.

  Returns a map with node IDs as keys and the full node struct as values.
  Each node can be looked up by its ID or any of its aliases.

  ## Parameters
  - `cluster_name` - Cluster name (without "cluster-" prefix)

  ## Returns
  - `{:ok, identifiers_map}` - Map of identifier => node
  - `{:error, :not_found}` - Cluster doesn't exist

  ## Example
      {:ok, map} = list_node_identifiers_by_cluster("default")
      # map = %{
      #   "abc-123" => %Node{id: "abc-123", ...},
      #   "test" => %Node{id: "abc-123", ...},  # alias
      #   "def-456" => %Node{id: "def-456", ...}
      # }
  """
  @spec list_node_identifiers_by_cluster(String.t()) :: {:ok, map()} | {:error, :not_found}
  def list_node_identifiers_by_cluster(cluster_name) do
    case get_cluster(cluster_name) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, cluster} ->
        nodes = Repo.all(from(n in Node, where: n.cluster_id == ^cluster.id, preload: [:cluster, aliases: :cluster]))

        # Build map of all identifiers (node IDs + aliases) => node
        identifiers_map =
          Enum.reduce(nodes, %{}, fn node, acc ->
            # Add node ID
            acc = Map.put(acc, node.id, node)

            # Add all aliases
            Enum.reduce(node.aliases, acc, fn alias_record, inner_acc ->
              Map.put(inner_acc, alias_record.name, node)
            end)
          end)

        {:ok, identifiers_map}
    end
  end

  # ===========================================================================
  # Enrollment Key functions
  # ===========================================================================

  @doc """
  Creates or retrieves an enrollment key for a cluster.

  ## Key Types

  ### Default (default behavior)
  Retrieves the Netmaker auto-generated default enrollment key.
  - Unlimited uses
  - No expiration
  - Not tracked in our DB
  - Use for: Production edge nodes, mass deployments

  ### Custom
  Creates a new key with user-specified expiry and uses.
  - Configurable expiration (default: 1 hour)
  - Configurable uses (default: 1)
  - Not tracked in DB (tagged for audit trail in Netmaker)
  - Use for: Controlled/time-limited registrations
  """
  @spec create_enrollment_key(Cluster.t(), map()) ::
          {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :service_unavailable}
  def create_enrollment_key(%Cluster{} = cluster, params \\ %{}) do
    with {:ok, attrs} <- Forms.CreateEnrollmentKeyForm.changeset(params) do
      # Get key_type (required) and apply defaults for optional fields
      key_type = Map.fetch!(attrs, "key_type")
      expiration = Map.get(attrs, "expiration", 3600)
      uses_remaining = Map.get(attrs, "uses_remaining", 1)
      network_name = node_network_name(cluster)

      case key_type do
        "default" ->
          # Retrieve the default key from Netmaker (created automatically with network)
          case Vpn.get_default_enrollment_key(network_name) do
            {:ok, token} ->
              {:ok, %{token: token, key_type: "default"}}

            {:error, _reason} ->
              {:error, :service_unavailable}
          end

        "custom" ->
          # Create a custom key with user-specified expiry/uses
          # Generate tag for audit trail (not tracked in DB)
          timestamp = System.system_time(:millisecond)
          random = 4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
          tag = "custom-#{timestamp}-#{random}"

          case Vpn.create_enrollment_key(network_name, %{
                 expiration: expiration,
                 uses_remaining: uses_remaining,
                 tags: [tag]
               }) do
            {:ok, netmaker_key} ->
              {:ok, %{token: netmaker_key["token"], key_type: "custom"}}

            {:error, _reason} ->
              {:error, :service_unavailable}
          end
      end
    end
  end

  @doc """
  Reconciles clusters and their node membership between database (source of truth) and Netmaker.

  For each cluster:
  1. Gets nodes that SHOULD be in the network (from DB)
  2. Gets nodes that ARE in the network (from Netmaker)
  3. Cleans up orphaned aliases (nodes not in DB or not in Netmaker)
  4. Adds missing nodes (DB says yes, Netmaker says no)
  5. Removes extra nodes (Netmaker says yes, DB says no)
  6. Cleans up orphaned clusters (exist in DB but network doesn't exist in Netmaker)
  7. Cleans up ghost aliases (exist in DB but DNS doesn't exist in Netmaker)

  Only processes edge nodes (those belonging to edge agents, identified by having a DB record).
  Admin nodes and staff machines are not touched.

  Processes all clusters in batches of 500.

  Returns statistics about the reconciliation operation.
  """
  @spec reconcile_clusters() :: map()
  def reconcile_clusters do
    reconcile_clusters_paginated(1, %{
      clusters_processed: 0,
      nodes_added: 0,
      nodes_removed: 0,
      nodes_deleted: 0,
      clusters_deleted: 0,
      aliases_cleaned: 0,
      ghost_aliases_cleaned: 0,
      errors: 0
    })
  end

  defp reconcile_clusters_paginated(page, acc) do
    {:ok, {clusters, meta}} = list_clusters(%{"page_size" => "500", "page" => to_string(page)})

    if Enum.empty?(clusters) do
      # No more clusters to process
      Logger.info("Cluster reconciliation completed: #{inspect(acc)}")
      acc
    else
      # Get all DB nodes for this batch of clusters
      cluster_ids = Enum.map(clusters, & &1.id)

      db_nodes_by_cluster =
        from(n in Node, where: n.cluster_id in ^cluster_ids, preload: [:cluster])
        |> Repo.all()
        |> Enum.group_by(& &1.cluster_id)

      Logger.info("Processing page #{page}: #{length(clusters)} clusters")

      # Process this batch of clusters
      result =
        Enum.reduce(clusters, acc, fn cluster, cluster_acc ->
          reconcile_single_cluster(cluster, db_nodes_by_cluster[cluster.id] || [], cluster_acc)
        end)

      # Clean up orphaned clusters for this batch
      result_with_clusters = cleanup_orphaned_clusters(clusters, result)

      # Clean up ghost aliases for this batch
      result_with_ghost_aliases = cleanup_ghost_aliases(clusters, result_with_clusters)

      # Check if there are more pages
      if meta.has_next_page? do
        # Process next page
        reconcile_clusters_paginated(page + 1, result_with_ghost_aliases)
      else
        # All pages processed
        Logger.info("Cluster reconciliation completed: #{inspect(result_with_ghost_aliases)}")
        result_with_ghost_aliases
      end
    end
  end

  defp reconcile_single_cluster(cluster, db_nodes, acc) do
    network_name = node_network_name(cluster)

    Logger.debug("Reconciling cluster #{cluster.name} (network: #{network_name})")

    # Get what SHOULD be in this network (from DB)
    expected_host_ids = MapSet.new(db_nodes, & &1.netmaker_host_id)

    # Get what IS in this network (from Netmaker)
    case Vpn.list_nodes(network_name) do
      {:ok, netmaker_nodes} ->
        # Extract host IDs from Netmaker nodes
        # These are all nodes in the network, including admin nodes and staff machines
        actual_host_ids =
          netmaker_nodes
          |> Enum.map(& &1["hostid"])
          |> Enum.reject(&is_nil/1)
          |> MapSet.new()

        # Nodes in DB but NOT in this Netmaker network
        # Could be: deleted (host gone), in limbo (changing clusters), or moved to another cluster
        orphaned_in_db = MapSet.difference(expected_host_ids, actual_host_ids)

        orphaned_nodes =
          Enum.filter(db_nodes, fn node -> node.netmaker_host_id in orphaned_in_db end)

        # Clean up aliases for orphaned nodes
        aliases_cleaned = cleanup_orphaned_aliases(orphaned_nodes)

        # Delete orphaned nodes from DB if host doesn't exist in Netmaker at all
        deleted = delete_orphaned_nodes(orphaned_nodes)

        # Add missing nodes (DB says yes, Netmaker says no, but host exists in Netmaker)
        # These are hosts in limbo between cluster changes
        missing = MapSet.difference(expected_host_ids, actual_host_ids)
        added = add_missing_nodes(missing, network_name, cluster.name)

        # Remove extra nodes (Netmaker says yes, but DB says this cluster shouldn't have them)
        # These are nodes that moved to another cluster but weren't removed from old network
        extra_in_netmaker = MapSet.difference(actual_host_ids, expected_host_ids)

        # Only remove if we manage this host (it's in our DB somewhere)
        all_db_host_ids =
          from(n in Node, select: n.netmaker_host_id)
          |> Repo.all()
          |> MapSet.new()

        managed_extra = MapSet.intersection(extra_in_netmaker, all_db_host_ids)
        removed = remove_extra_nodes(managed_extra, network_name, cluster.name)

        %{
          clusters_processed: acc.clusters_processed + 1,
          nodes_added: acc.nodes_added + added,
          nodes_removed: acc.nodes_removed + removed,
          nodes_deleted: acc.nodes_deleted + deleted,
          clusters_deleted: acc.clusters_deleted,
          aliases_cleaned: acc.aliases_cleaned + aliases_cleaned,
          errors: acc.errors
        }

      {:error, reason} ->
        Logger.error("Failed to list nodes for cluster #{cluster.name}: #{inspect(reason)}")

        %{acc | errors: acc.errors + 1}
    end
  end

  defp add_missing_nodes(host_ids, network_name, cluster_name) do
    Enum.reduce(host_ids, 0, fn host_id, count ->
      case Vpn.add_host_to_network(host_id, network_name) do
        {:ok, _} ->
          Logger.info("Reconciliation: Added host #{host_id} to network #{network_name} (cluster: #{cluster_name})")

          count + 1

        {:error, reason} ->
          Logger.warning("Reconciliation: Failed to add host #{host_id} to network #{network_name}: #{inspect(reason)}")

          count
      end
    end)
  end

  defp remove_extra_nodes(host_ids, network_name, cluster_name) do
    Enum.reduce(host_ids, 0, fn host_id, count ->
      case Vpn.remove_host_from_network(host_id, network_name) do
        {:ok, _} ->
          Logger.info("Reconciliation: Removed host #{host_id} from network #{network_name} (cluster: #{cluster_name})")

          count + 1

        {:error, reason} ->
          Logger.warning(
            "Reconciliation: Failed to remove host #{host_id} from network #{network_name}: #{inspect(reason)}"
          )

          count
      end
    end)
  end

  defp delete_orphaned_nodes(orphaned_nodes) do
    Enum.reduce(orphaned_nodes, 0, fn node, count ->
      # Check if host exists in Netmaker at all
      case Vpn.get_host(node.netmaker_host_id) do
        {:ok, _host} ->
          # Host exists in Netmaker (probably in limbo between clusters)
          # Don't delete from DB - add_missing_nodes will handle re-adding
          Logger.debug(
            "Reconciliation: Host #{node.netmaker_host_id} exists in Netmaker, skipping DB deletion (node in limbo)"
          )

          count

        {:error, :not_found} ->
          # Host doesn't exist in Netmaker - safe to delete from DB
          # This means deletion was attempted and Netmaker succeeded but DB failed
          Logger.info("Reconciliation: Deleting orphaned node #{node.id} from DB (host not found in Netmaker)")

          case Repo.delete(node) do
            {:ok, _} ->
              # Emit event for metadata recomputation
              broadcast_metadata_event({:node_deleted, node.id, node.cluster_id})

              count + 1

            {:error, changeset} ->
              Logger.error("Reconciliation: Failed to delete orphaned node #{node.id}: #{inspect(changeset)}")

              count
          end

        {:error, reason} ->
          Logger.warning("Reconciliation: Failed to check if host #{node.netmaker_host_id} exists: #{inspect(reason)}")

          count
      end
    end)
  end

  defp cleanup_orphaned_clusters(clusters, acc) do
    Enum.reduce(clusters, acc, fn cluster, result ->
      network_name = node_network_name(cluster)

      # Check if network exists in Netmaker
      case Vpn.get_network(network_name) do
        {:ok, _network} ->
          # Network exists, cluster is fine
          result

        {:error, :not_found} ->
          # Network doesn't exist - cluster should be deleted from DB
          # This means deletion was attempted and Netmaker succeeded but DB failed
          Logger.info("Reconciliation: Deleting orphaned cluster #{cluster.id} from DB (network not found in Netmaker)")

          case Repo.delete(cluster) do
            {:ok, _} ->
              # Emit event for metadata recomputation
              broadcast_metadata_event({:cluster_deleted, cluster.id})

              %{result | clusters_deleted: result.clusters_deleted + 1}

            {:error, changeset} ->
              Logger.error("Reconciliation: Failed to delete orphaned cluster #{cluster.id}: #{inspect(changeset)}")

              %{result | errors: result.errors + 1}
          end

        {:error, reason} ->
          Logger.warning("Reconciliation: Failed to check if network #{network_name} exists: #{inspect(reason)}")

          %{result | errors: result.errors + 1}
      end
    end)
  end

  @doc """
  Cleans up all aliases for a single node.

  Deletes DNS entries from Netmaker and removes alias records from DB.
  Best-effort - logs warnings on failures but continues cleanup.

  Used when a node changes clusters (all aliases become invalid).
  """
  @spec cleanup_node_aliases(Node.t()) :: :ok
  def cleanup_node_aliases(%Node{} = node) do
    node = Repo.preload(node, [:cluster, aliases: :cluster])

    Enum.each(node.aliases, fn alias_record ->
      cleanup_single_alias(alias_record)
    end)
  end

  @doc """
  Cleans up orphaned aliases for multiple nodes.

  Used by reconciliation worker to clean up aliases for nodes that:
  - No longer exist in Netmaker (left network, deleted)
  - Exist in DB but not in the current network

  Returns count of cleaned aliases.
  """
  @spec cleanup_orphaned_aliases([Node.t()]) :: non_neg_integer()
  def cleanup_orphaned_aliases(nodes) do
    Enum.reduce(nodes, 0, fn node, count ->
      node = Repo.preload(node, [:cluster, aliases: :cluster])
      alias_count = length(node.aliases)

      if alias_count > 0 do
        Logger.info("Cleaning up #{alias_count} orphaned alias(es) for node #{node.id}")
        cleanup_node_aliases(node)
        count + alias_count
      else
        count
      end
    end)
  end

  defp cleanup_single_alias(%Alias{} = alias_record) do
    network_name = node_network_name(alias_record.cluster)
    dns_hostname = Alias.dns_hostname(alias_record)

    # 1. Try to delete DNS entry (best-effort)
    case Vpn.delete_dns_entry(network_name, dns_hostname) do
      {:ok, _} ->
        Logger.info("Deleted DNS entry for alias #{alias_record.name}: #{dns_hostname}")

      {:error, :not_found} ->
        Logger.debug("DNS entry already deleted for alias #{alias_record.name}: #{dns_hostname}")

      {:error, :service_unavailable} ->
        Logger.warning("Failed to delete DNS entry for alias #{alias_record.name}: service unavailable")
    end

    # 2. Delete from DB
    case Repo.delete(alias_record) do
      {:ok, _} ->
        Logger.debug("Deleted alias record: #{alias_record.name}")

      {:error, reason} ->
        Logger.error("Failed to delete alias record #{alias_record.name}: #{inspect(reason)}")
    end
  end

  # ===========================================================================
  # Alias functions
  # ===========================================================================

  @doc """
  Lists aliases with filtering and pagination.

  Supports filtering by:
  - `name` - Text search with wildcard support
  - `cluster_name` - Text search with wildcard support (requires join)
  - `inserted_at__gte/lte` - Date range filter
  """
  @spec list_aliases(map()) :: {:ok, {[Alias.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_aliases(params \\ %{}) do
    # Parse params into Flop format
    flop_params = RequestParser.parse(params)

    # Extract cluster_name filters (join-based, handle separately)
    {cluster_name_filters, other_filters} =
      Enum.split_with(flop_params[:filters] || [], fn filter ->
        filter.field == :cluster_name
      end)

    # Build base query with cluster preload
    base_query =
      from(a in Alias,
        join: c in assoc(a, :cluster),
        preload: [cluster: c]
      )

    # Apply cluster_name filters if present
    query_with_cluster_filter =
      if cluster_name_filters == [] do
        base_query
      else
        apply_cluster_name_filters(base_query, cluster_name_filters)
      end

    # Remove cluster_name filters from Flop params (handled above)
    flop_params = Map.put(flop_params, :filters, other_filters)

    # Run Flop query
    case Flop.validate_and_run(query_with_cluster_filter, flop_params,
           for: Alias,
           replace_invalid_params: true
         ) do
      {:ok, {aliases, meta}} ->
        {:ok, {aliases, meta}}

      {:error, meta} ->
        {:error, meta}
    end
  end

  @doc """
  Gets a single alias by ID.

  ## Parameters
  - `id` - The alias ID

  ## Returns
  - `{:ok, alias}` - Alias found (with cluster preloaded)
  - `{:error, :not_found}` - Alias doesn't exist or invalid UUID

  ## Examples

      iex> get_alias(alias_id)
      {:ok, %Alias{name: "web-server", cluster: %Cluster{}}}
  """
  @spec get_alias(String.t()) :: {:ok, Alias.t()} | {:error, :not_found}
  def get_alias(id) do
    case Repo.get(Alias, id) do
      nil -> {:error, :not_found}
      alias_record -> {:ok, Repo.preload(alias_record, :cluster)}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc """
  Creates an alias for a node and its DNS entry.

  Flow:
  1. Check Netmaker health (fail fast if service unavailable)
  2. Validate input
  3. Query node IP from Netmaker (required for DNS entry)
  4. Create DB record
  5. Create DNS entry in Netmaker (rollback DB on failure)

  If health check fails, returns service unavailable immediately.
  If node not found in Netmaker or has no IP, returns service unavailable.
  If DB creation fails, returns validation error.
  If DNS creation fails, deletes DB record and returns service unavailable.

  This ensures "alias in DB but DNS not in Netmaker" always means failed deletion,
  allowing reconciliation to safely delete orphaned DB aliases.

  ## Parameters
  - `node` - The node to create an alias for (must have cluster preloaded)
  - `params` - Map with "name" key

  ## Returns
  - `{:ok, alias}` - Alias created successfully
  - `{:error, changeset}` - Validation failed
  - `{:error, :service_unavailable}` - Netmaker health check failed, node not found, or DNS creation failed

  ## Examples

      iex> create_alias(node, %{"name" => "web-server"})
      {:ok, %Alias{name: "web-server", node_id: "abc-123"}}
  """
  @spec create_alias(Node.t(), map()) ::
          {:ok, Alias.t()} | {:error, Ecto.Changeset.t()} | {:error, :service_unavailable}
  def create_alias(%Node{} = node, params) do
    with {:ok, attrs} <- Forms.CreateAliasForm.changeset(params),
         # Check Netmaker health before proceeding
         :ok <- Vpn.health_check() do
      # 1. Ensure node has cluster preloaded
      node = Repo.preload(node, :cluster)

      # 2. Query Netmaker for node's IP address (required for DNS entry)
      network_name = node_network_name(node.cluster)

      case Vpn.find_node_by_host(network_name, node.netmaker_host_id) do
        {:ok, %{"address" => address}} when is_binary(address) and address != "" ->
          # 3. Build attrs with node_id and cluster_id
          alias_attrs =
            Map.merge(attrs, %{
              "node_id" => node.id,
              "cluster_id" => node.cluster_id
            })

          # 4. Create DB record
          changeset = Alias.changeset(%Alias{}, alias_attrs)

          case Repo.insert(changeset) do
            {:ok, alias_record} ->
              alias_record = Repo.preload(alias_record, :cluster)

              # 5. Create DNS entry in Netmaker (rollback DB on failure)
              ip_address = address |> String.split("/") |> List.first()
              dns_hostname = Alias.dns_hostname(alias_record)

              case Vpn.create_dns_entry(network_name, %{
                     name: dns_hostname,
                     address: ip_address
                   }) do
                {:ok, _} ->
                  Logger.info("Created DNS entry for alias #{alias_record.name}: #{dns_hostname} -> #{ip_address}")
                  {:ok, alias_record}

                {:error, :service_unavailable} = error ->
                  # Netmaker DNS creation failed - rollback DB insert
                  Logger.warning("Netmaker DNS creation failed, rolling back DB alias: #{alias_record.name}")
                  Repo.delete(alias_record)
                  error
              end

            {:error, changeset} ->
              {:error, changeset}
          end

        {:ok, _node} ->
          Logger.error("Node #{node.netmaker_host_id} has no IP address in Netmaker")
          {:error, :service_unavailable}

        {:error, :not_found} ->
          Logger.error("Node #{node.netmaker_host_id} not found in Netmaker")
          {:error, :service_unavailable}

        {:error, :service_unavailable} ->
          Logger.error("Failed to query Netmaker nodes")
          {:error, :service_unavailable}
      end
    end
  end

  @doc """
  Deletes an alias and its DNS entry.

  Flow (Netmaker-first):
  1. Delete DNS entry from Netmaker FIRST
  2. Delete from DB

  If Netmaker deletion fails (except :not_found), operation stops and returns error.
  If Netmaker returns :not_found, continues with DB deletion (DNS already gone).

  This ensures "alias in DB but DNS not in Netmaker" always means failed deletion,
  allowing reconciliation to safely delete orphaned DB aliases.

  Returns `{:ok, alias}`, `{:error, changeset}` (DB failure), or `{:error, :service_unavailable}` (Netmaker failure).
  """
  @spec delete_alias(Alias.t()) :: {:ok, Alias.t()} | {:error, Ecto.Changeset.t()} | {:error, :service_unavailable}
  def delete_alias(%Alias{} = alias_record) do
    alias_record = Repo.preload(alias_record, :cluster)
    network_name = node_network_name(alias_record.cluster)
    dns_hostname = Alias.dns_hostname(alias_record)

    # 1. Delete DNS entry from Netmaker FIRST
    case Vpn.delete_dns_entry(network_name, dns_hostname) do
      {:ok, _} ->
        Logger.info("Deleted DNS entry for alias #{alias_record.name}: #{dns_hostname}")
        delete_alias_from_db(alias_record)

      {:error, :not_found} ->
        # DNS already gone - continue with DB deletion
        Logger.info("DNS entry already deleted for alias #{alias_record.name}: #{dns_hostname}")
        delete_alias_from_db(alias_record)

      {:error, :service_unavailable} = error ->
        # Netmaker failed - stop operation
        Logger.error("Failed to delete DNS entry for alias #{alias_record.name}, aborting alias deletion")
        error
    end
  end

  defp delete_alias_from_db(%Alias{} = alias_record) do
    case Repo.delete(alias_record) do
      {:ok, deleted_alias} ->
        {:ok, deleted_alias}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Returns a changeset for tracking alias changes (for forms).

  ## Examples

      iex> change_alias(alias_record)
      %Ecto.Changeset{data: %Alias{}}
  """
  @spec change_alias(Alias.t(), map()) :: Ecto.Changeset.t()
  def change_alias(%Alias{} = alias_record, attrs \\ %{}) do
    Alias.changeset(alias_record, attrs)
  end

  @doc """
  Cleans up ghost aliases (exist in DB but DNS doesn't exist in Netmaker).

  For each cluster:
  1. Gets all aliases from DB
  2. Gets all DNS entries from Netmaker
  3. Identifies ghost aliases (in DB but not in Netmaker DNS)
  4. Deletes ghost aliases from DB

  This handles cases where:
  - Alias deletion succeeded in Netmaker but DB deletion failed
  - DNS entry was manually deleted from Netmaker
  - Netmaker network was recreated, losing all custom DNS entries

  Given our delete-first flow (Netmaker → DB), "alias in DB but DNS not in Netmaker"
  indicates a failed deletion that should be cleaned up by removing the DB record.

  Returns count of cleaned ghost aliases.
  """
  @spec cleanup_ghost_aliases([Cluster.t()], map()) :: map()
  def cleanup_ghost_aliases(clusters, acc) do
    Enum.reduce(clusters, acc, fn cluster, result ->
      network_name = node_network_name(cluster)

      # Get all aliases for this cluster from DB
      db_aliases = Repo.all(from(a in Alias, where: a.cluster_id == ^cluster.id, preload: [:cluster]))

      if Enum.empty?(db_aliases) do
        # No aliases to check
        result
      else
        # Get all DNS entries from Netmaker for this network
        case Vpn.list_dns_entries(network_name) do
          {:ok, netmaker_dns_entries} ->
            # Build set of DNS hostnames that exist in Netmaker
            netmaker_dns_names = MapSet.new(netmaker_dns_entries, & &1["name"])

            # Find ghost aliases (in DB but DNS not in Netmaker)
            ghost_aliases =
              Enum.filter(db_aliases, fn alias_record ->
                dns_hostname = Alias.dns_hostname(alias_record)
                not MapSet.member?(netmaker_dns_names, dns_hostname)
              end)

            if Enum.empty?(ghost_aliases) do
              result
            else
              Logger.info("Found #{length(ghost_aliases)} ghost alias(es) in cluster #{cluster.name}")

              # Delete ghost aliases from DB (DNS already doesn't exist)
              deleted_count =
                Enum.reduce(ghost_aliases, 0, fn alias_record, count ->
                  case Repo.delete(alias_record) do
                    {:ok, _} ->
                      Logger.info(
                        "Reconciliation: Deleted ghost alias #{alias_record.name} from DB " <>
                          "(DNS entry doesn't exist in Netmaker)"
                      )

                      count + 1

                    {:error, changeset} ->
                      Logger.error(
                        "Reconciliation: Failed to delete ghost alias #{alias_record.name}: #{inspect(changeset)}"
                      )

                      count
                  end
                end)

              %{result | ghost_aliases_cleaned: result.ghost_aliases_cleaned + deleted_count}
            end

          {:error, reason} ->
            Logger.warning("Reconciliation: Failed to list DNS entries for cluster #{cluster.name}: #{inspect(reason)}")

            %{result | errors: result.errors + 1}
        end
      end
    end)
  end
end
