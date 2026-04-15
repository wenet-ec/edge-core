# edge_admin/lib/edge_admin/nodes/nodes.ex
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

  Two sources of state must be kept in sync: our PostgreSQL DB and Netmaker (the VPN
  provider). There is no transaction spanning both — every operation that touches both
  systems has a partial-failure window. The reconciler (`reconcile_clusters/0`, called
  periodically) is what heals drift. Understand the reconciler before changing any
  create/delete ordering here.

  ### Ordering rules (why they are what they are)

  **Cluster create — Netmaker first, then DB:**
  Netmaker does its own full CIDR overlap check across all networks it knows about,
  including `admin-cluster-*` networks that our DB has no record of. Our local
  `SubnetOverlapCheck` only checks `cluster-*` ranges in our DB — it cannot detect
  conflicts with admin networks. Going DB-first would allow a subnet that passes our
  check but fails Netmaker's, resulting in a wasted DB insert and rollback. Going
  Netmaker-first lets Netmaker be the authority on IP space. If DB insert fails after
  Netmaker succeeds, the ghost network is cleaned by `cleanup_ghost_networks/1` in the
  next reconcile sweep (safe because we only ever delete `cluster-*` prefixed networks).

  **Cluster delete — Netmaker first, then DB:**
  If we deleted DB first and Netmaker failed, the network would be permanently orphaned
  (reconciler only iterates DB clusters, so it would never see it). Going Netmaker-first
  means a DB delete failure leaves "cluster in DB, network gone from Netmaker" — which
  `cleanup_orphaned_clusters/2` explicitly detects and cleans up.

  **Alias create — read IP from Netmaker, then DB, then write DNS to Netmaker:**
  The node's VPN IP is only known to Netmaker; we must fetch it. The DB insert anchors
  the alias record. The DNS write is the final step. If DNS write fails, we rollback the
  DB insert. If rollback also fails, `cleanup_ghost_aliases/2` in the reconciler will
  clean the orphaned DB record. Ghost DNS entries (DNS in Netmaker, no DB record) are
  cleaned by the Netmaker→DB direction of `cleanup_ghost_aliases/2`.

  **Alias delete — Netmaker first, then DB:**
  Same reasoning as cluster delete — DB-first would create permanently invisible orphans.

  ### Reconciler directions (both are needed)

  `cleanup_orphaned_clusters/2` — DB has cluster, Netmaker doesn't:
  Handles failed delete (Netmaker succeeded, DB delete failed) and manual Netmaker
  deletions. Fix: delete the DB record.

  `cleanup_ghost_networks/1` — Netmaker has `cluster-*` network, DB doesn't:
  Handles failed create (Netmaker succeeded, DB insert failed). Fix: delete the Netmaker
  network. Safety: we only touch networks with the `cluster-` prefix — `admin-cluster-*`
  networks are admin infrastructure and are never touched here. The prefix contract is
  enforced by `Vpn.build_network_name/2`.

  `cleanup_ghost_aliases/2` — bidirectional alias cleanup, same logic applied to DNS.

  ### Subnet pool and scale

  Cluster subnets are carved from `CLUSTER_AUTO_GENERATED_RANGES` (default: CGNAT
  `100.64.0.0/10`) at `CLUSTER_SUBNET_PREFIX` (default: `/24`). This gives a hard cap
  of 16,384 clusters per core (4,194,304 addresses ÷ 256 per /24). If the pool is
  exhausted, start a new core — do not expand the range or change the prefix on an
  existing core. `GET /api/networks` in Netmaker has no pagination (full table scan);
  at the 16k ceiling the response is ~5-8MB — acceptable for a periodic reconcile call.

  ### Known brittleness / glue code warnings

  This module is the glue between our DB and Netmaker. It is inherently brittle because:

  - There is no distributed transaction. Every two-phase operation has a failure window.
    The reconciler heals it eventually but "eventually" can mean up to one reconcile
    interval (~minutes). Don't assume operations are atomic.

  - `create_alias/2` fetches the node's VPN IP from Netmaker at call time. If the node
    re-enrolls and gets a new IP, the DNS entry points to the old IP forever — there is
    no reconciliation path that *updates* DNS entries, only creates or deletes them.
    This is a known silent correctness gap.

  - `cleanup_ghost_networks/1` deletes by prefix convention, not by any Netmaker-side
    ownership marker. If something outside this system ever creates a `cluster-*` network
    in Netmaker, the reconciler will delete it. The prefix contract must be maintained.

  - The reconciler runs `cleanup_orphaned_clusters/2` per page (batched with cluster
    iteration) but `cleanup_ghost_networks/1` only at the end of the full sweep. This
    means a ghost network created during a sweep may not be cleaned until the next full
    run. Acceptable — ghost networks are harmless, just wasteful.

  - `reconcile_cluster/1` (single-cluster worker path) does NOT run
    `cleanup_ghost_networks/1`. It only has context for one cluster, not the global
    Netmaker state. Ghost network cleanup only happens in `reconcile_clusters/0`.

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
  alias EdgeAdmin.EdgeClusters.AgentClient
  alias EdgeAdmin.EventBroker
  alias EdgeAdmin.EventBroker.Events
  alias EdgeAdmin.Nodes.Checks
  alias EdgeAdmin.Nodes.Forms
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey
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

  # Adds nodelimit to Netmaker network opts when a limit is set
  defp maybe_put_nodelimit(opts, nil), do: opts
  defp maybe_put_nodelimit(opts, limit), do: Map.put(opts, :nodelimit, limit)

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

    # Extract has_node_limit filter (virtual field, handle separately)
    {has_node_limit_filters, other_filters} =
      Enum.split_with(other_filters, fn filter ->
        filter.field == :has_node_limit
      end)

    # Extract ilike filters for string fields — Flop's :ilike wraps values in %..%
    # and escapes any existing % characters, breaking wildcard patterns like "def%".
    # Apply these as raw Ecto ilike/2 clauses instead.
    {ilike_filters, flop_params} =
      RequestParser.split_ilike_filters(
        Map.put(flop_params, :filters, other_filters),
        [:name, :ipv4_range]
      )

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

    # Apply has_node_limit filter if present
    base_query =
      if has_node_limit_filters == [] do
        base_query
      else
        apply_has_node_limit_filters(base_query, has_node_limit_filters)
      end

    # Apply ilike filters directly via Ecto (bypassing Flop's add_wildcard)
    base_query = apply_cluster_ilike_filters(base_query, ilike_filters)

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

  defp apply_has_node_limit_filters(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_has_node_limit_filter(acc, filter) end)
  end

  defp apply_has_node_limit_filter(query, %{op: :==, value: v}) when v in [true, "true"] do
    from(c in query, where: not is_nil(c.node_limit))
  end

  defp apply_has_node_limit_filter(query, %{op: :==, value: v}) when v in [false, "false"] do
    from(c in query, where: is_nil(c.node_limit))
  end

  defp apply_has_node_limit_filter(query, _), do: query

  # Apply ilike filters for string fields directly via Ecto, bypassing Flop's add_wildcard
  # which escapes % characters and wraps values in %..%, breaking user-supplied patterns.
  defp apply_cluster_ilike_filters(query, filters) do
    Enum.reduce(filters, query, fn %{field: field, value: value}, acc ->
      from(c in acc, where: ilike(field(c, ^field), ^value))
    end)
  end

  # Apply node_count filters using HAVING clause
  defp apply_node_count_filters(query, filters) do
    Enum.reduce(filters, query, fn filter, acc_query ->
      apply_node_count_filter(acc_query, filter)
    end)
  end

  defp apply_node_count_filter(query, %{op: :>=, value: value}) when is_integer(value),
    do: from([c, n] in query, having: count(n.id) >= ^value)

  defp apply_node_count_filter(query, %{op: :>=, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) >= ^num)
      _ -> query
    end
  end

  defp apply_node_count_filter(query, %{op: :>, value: value}) when is_integer(value),
    do: from([c, n] in query, having: count(n.id) > ^value)

  defp apply_node_count_filter(query, %{op: :>, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) > ^num)
      _ -> query
    end
  end

  defp apply_node_count_filter(query, %{op: :<=, value: value}) when is_integer(value),
    do: from([c, n] in query, having: count(n.id) <= ^value)

  defp apply_node_count_filter(query, %{op: :<=, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) <= ^num)
      _ -> query
    end
  end

  defp apply_node_count_filter(query, %{op: :<, value: value}) when is_integer(value),
    do: from([c, n] in query, having: count(n.id) < ^value)

  defp apply_node_count_filter(query, %{op: :<, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) < ^num)
      _ -> query
    end
  end

  defp apply_node_count_filter(query, %{op: :==, value: value}) when is_integer(value),
    do: from([c, n] in query, having: count(n.id) == ^value)

  defp apply_node_count_filter(query, %{op: :==, value: value}) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> from([c, n] in query, having: count(n.id) == ^num)
      _ -> query
    end
  end

  defp apply_node_count_filter(query, %{op: :!=, value: value}) when is_integer(value),
    do: from([c, n] in query, having: count(n.id) != ^value)

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
          id -> if use_prefix, do: Vpn.build_vpn_name(id, prefix: :node), else: id
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

  Returns `{:ok, cluster}`, `{:error, changeset}` (validation), `{:error, {:conflict, reason}}` (CIDR overlap), or `{:error, :service_unavailable}` (health check or Netmaker failure).
  """
  @spec create_cluster(map()) ::
          {:ok, Cluster.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:conflict, String.t()}}
          | {:error, :service_unavailable}
  def create_cluster(attrs \\ %{}) do
    with {:ok, validated_attrs} <- Forms.CreateClusterForm.changeset(attrs),
         # Check Netmaker health before proceeding
         :ok <- Vpn.netmaker_health_check(),
         existing_ranges = Repo.all(from(c in Cluster, select: c.ipv4_range)),
         :ok <- Checks.SubnetOverlapCheck.check(validated_attrs["ipv4_range"], existing_ranges),
         ipv4_range = validated_attrs["ipv4_range"] || Vpn.generate_next_subnet(existing_ranges),
         cluster_attrs = Map.put(validated_attrs, "ipv4_range", ipv4_range),
         {:ok, cluster} <-
           %Cluster{}
           |> Cluster.changeset(cluster_attrs)
           |> Repo.insert()
           |> Repo.normalize_conflict([:name, :ipv4_range]) do
      # DB insert succeeded - now create Netmaker network
      network_name = node_network_name(cluster)

      netmaker_opts = maybe_put_nodelimit(%{addressrange: ipv4_range}, cluster.node_limit)

      case Vpn.create_network(network_name, netmaker_opts) do
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

  node_limit is enforced by this system only. Netmaker has the field on its network
  model but no server-side update endpoint or enforcement logic as of the current version.

  ## Parameters
  - `cluster` - The cluster struct to update
  - `params` - Raw request params (validated through UpdateClusterForm)

  ## Returns
  - `{:ok, cluster}` - Update succeeded
  - `{:error, changeset}` - Validation failed
  """
  @spec update_cluster(Cluster.t(), map()) ::
          {:ok, Cluster.t()} | {:error, Ecto.Changeset.t()}
  def update_cluster(%Cluster{} = cluster, params) do
    with {:ok, attrs} <- Forms.UpdateClusterForm.changeset(params),
         :ok <- Checks.NodeLimitBelowCountCheck.check(cluster, Map.get(attrs, "node_limit")),
         {:ok, updated_cluster} <-
           cluster
           |> Cluster.changeset(attrs)
           |> Repo.update() do
      {:ok, Repo.preload(updated_cluster, :nodes)}
    end
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

  Returns `{:ok, cluster}`, `{:error, {:conflict, reason}}` (cluster has nodes), or `{:error, :service_unavailable}` (Netmaker failure).
  """
  @spec delete_cluster(Cluster.t()) ::
          {:ok, Cluster.t()} | {:error, {:conflict, String.t()}} | {:error, :service_unavailable}
  def delete_cluster(%Cluster{} = cluster) do
    case Checks.ClusterNotEmptyCheck.check(cluster) do
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

      {:error, {:conflict, _}} = error ->
        error
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
    "http://#{Node.vpn_hostname(node)}:#{port}"
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
  @spec change_node_cluster(Node.t(), map()) ::
          {:ok, Node.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def change_node_cluster(%Node{} = node, params) do
    with {:ok, new_cluster_name} <- Forms.ChangeNodeClusterForm.changeset(params),
         {:ok, new_cluster} <- get_cluster(new_cluster_name),
         :ok <- Checks.SameClusterCheck.check(node, new_cluster),
         :ok <- Checks.NodeLimitCheck.check(new_cluster) do
      old_cluster_id = node.cluster_id

      cleanup_node_aliases(node)

      case node |> Ecto.Changeset.change(cluster_id: new_cluster.id) |> Repo.update() do
        {:ok, updated_node} ->
          updated_node = Repo.preload(updated_node, [:cluster, aliases: :cluster], force: true)
          broadcast_metadata_event({:node_updated, node.id, old_cluster_id, new_cluster.id})
          sync_node_cluster_networks(node, new_cluster)

          EventBroker.enqueue(%Events.NodeClusterChanged{
            node: updated_node,
            previous_cluster_name: node.cluster.name
          })

          {:ok, updated_node}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  # Best-effort Netmaker network sync after a cluster change.
  # The reconciliation worker will fix any inconsistencies.
  defp sync_node_cluster_networks(node, new_cluster) do
    old_network_name = node_network_name(node.cluster)
    new_network_name = node_network_name(new_cluster)

    case Vpn.add_host_to_network(node.netmaker_host_id, new_network_name) do
      {:ok, _} ->
        Logger.info("Added host #{node.netmaker_host_id} to network #{new_network_name}")
        remove_host_from_old_network(node.netmaker_host_id, old_network_name)

      {:error, reason} ->
        Logger.warning(
          "Failed to add host #{node.netmaker_host_id} to new network #{new_network_name}: #{inspect(reason)}. " <>
            "Reconciliation worker will handle sync."
        )
    end
  end

  defp remove_host_from_old_network(host_id, old_network_name) do
    case Vpn.remove_host_from_network(host_id, old_network_name) do
      {:ok, _} ->
        Logger.info("Removed host #{host_id} from network #{old_network_name}")

      {:error, reason} ->
        Logger.warning(
          "Failed to remove host #{host_id} from old network #{old_network_name}: #{inspect(reason)}. " <>
            "Reconciliation worker will handle cleanup."
        )
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
        EventBroker.enqueue(%Events.NodeDeleted{node: deleted_node})
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
  @spec register_node(map()) ::
          {:ok, Node.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def register_node(params) do
    with {:ok, attrs} <- Forms.RegisterNodeForm.changeset(params) do
      %{"node_id" => node_id, "network_name" => network_name} = attrs

      cluster_name = String.replace_prefix(network_name, "cluster-", "")

      case get_cluster(cluster_name) do
        {:error, :not_found} ->
          Forms.RegisterNodeForm.add_netmaker_not_found_error()

        {:ok, cluster} ->
          existing_node = Repo.get(Node, node_id)
          is_new_node = is_nil(existing_node)

          with :ok <- if(is_new_node, do: Checks.NodeLimitCheck.check(cluster), else: :ok),
               {:ok, netmaker_host_id} <-
                 Vpn.get_host_id(Vpn.build_vpn_name(node_id, prefix: :node), network_name: network_name) do
            node_attrs = build_node_attrs(node_id, cluster, netmaker_host_id, attrs)
            upsert_node(node_attrs, existing_node, is_new_node, cluster)
          else
            {:error, _reason} -> Forms.RegisterNodeForm.add_netmaker_not_found_error()
          end
      end
    end
  end

  defp build_node_attrs(node_id, cluster, netmaker_host_id, attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    %{
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
      api_token: generate_token(),
      proxy_password: generate_token(),
      version: attrs["version"],
      self_update_enabled: attrs["self_update_enabled"]
    }
  end

  defp upsert_node(node_attrs, existing_node, is_new_node, cluster) do
    node_id = node_attrs.id
    result = if is_new_node, do: create_node(node_attrs), else: update_node(existing_node, node_attrs)

    case result do
      {:ok, node} ->
        node = Repo.preload(node, [:cluster], force: true)

        if is_new_node do
          broadcast_metadata_event({:node_created, node_id, cluster.id})
          EventBroker.enqueue(%Events.NodeRegistered{node: node})
        else
          EventBroker.enqueue(%Events.NodeReregistered{node: node})

          if existing_node.version != node_attrs.version do
            EventBroker.enqueue(%Events.NodeVersionChanged{
              node: node,
              previous_version: existing_node.version
            })
          end
        end

        {:ok, node}

      {:error, changeset} ->
        {:error, changeset}
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
    timeout = Application.get_env(:edge_admin, :health_check_timeout, 3_000)

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
    now = DateTime.truncate(DateTime.utc_now(), :second)
    start_time = System.monotonic_time(:millisecond)

    result =
      case AgentClient.ping(node, timeout) do
        :healthy ->
          update_node(node, %{status: "healthy", last_seen_at: now})
          maybe_publish_status_changed(node, "healthy")
          :healthy

        :unhealthy ->
          Logger.warning("Node #{node.id} is unhealthy (503 response)")
          update_node(node, %{status: "unhealthy", last_seen_at: now})
          maybe_publish_status_changed(node, "unhealthy")
          :unhealthy

        :unreachable ->
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
        # Never seen before
        nil -> true
        last_seen -> DateTime.before?(last_seen, five_minutes_ago)
      end

    if should_mark_unreachable do
      Logger.warning("Node #{node.id} is unreachable (no contact for > 5 minutes)")
      update_node(node, %{status: "unreachable"})
      maybe_publish_status_changed(node, "unreachable")
      :unreachable
    else
      Logger.debug("Node #{node.id} ping failed but last_seen_at is recent, keeping status: #{node.status}")
      # Keep existing status - might be using HTTP fallback
      String.to_existing_atom(node.status)
    end
  end

  defp maybe_publish_status_changed(node, new_status) do
    if node.status != new_status do
      EventBroker.enqueue(%Events.NodeStatusChanged{
        node: %{node | status: new_status},
        previous_status: node.status
      })
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

    # Extract ilike filters for string fields — Flop's :ilike wraps values in %..%
    # and escapes any existing % characters, breaking wildcard patterns like "1.*".
    # Apply these as raw Ecto ilike/2 clauses instead.
    {ilike_filters, flop_params} =
      RequestParser.split_ilike_filters(
        Map.put(flop_params, :filters, other_filters),
        [:version]
      )

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

    # Apply ilike filters directly via Ecto (bypassing Flop's add_wildcard)
    query_with_cluster_filter = apply_node_ilike_filters(query_with_cluster_filter, ilike_filters)

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

  defp apply_is_unlimited_filters(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_is_unlimited_filter(acc, filter) end)
  end

  defp apply_is_unlimited_filter(query, %{op: :==, value: v}) when v in [true, "true"] do
    from(k in query, where: is_nil(k.uses_remaining))
  end

  defp apply_is_unlimited_filter(query, %{op: :==, value: v}) when v in [false, "false"] do
    from(k in query, where: not is_nil(k.uses_remaining))
  end

  defp apply_is_unlimited_filter(query, _), do: query

  defp apply_is_spent_filters(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_is_spent_filter(acc, filter) end)
  end

  defp apply_is_spent_filter(query, %{op: :==, value: v}) when v in [true, "true"] do
    from(k in query, where: k.uses_remaining == 0)
  end

  defp apply_is_spent_filter(query, %{op: :==, value: v}) when v in [false, "false"] do
    from(k in query, where: k.uses_remaining != 0 or is_nil(k.uses_remaining))
  end

  defp apply_is_spent_filter(query, _), do: query

  defp apply_is_expired_filters(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_is_expired_filter(acc, filter) end)
  end

  defp apply_is_expired_filter(query, %{op: :==, value: v}) when v in [true, "true"] do
    now = DateTime.utc_now()
    from(k in query, where: not is_nil(k.expired_at) and k.expired_at < ^now)
  end

  defp apply_is_expired_filter(query, %{op: :==, value: v}) when v in [false, "false"] do
    now = DateTime.utc_now()
    from(k in query, where: is_nil(k.expired_at) or k.expired_at >= ^now)
  end

  defp apply_is_expired_filter(query, _), do: query

  defp apply_is_never_used_filters(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_is_never_used_filter(acc, filter) end)
  end

  defp apply_is_never_used_filter(query, %{op: :==, value: v}) when v in [true, "true"] do
    from(k in query, where: is_nil(k.last_used_at))
  end

  defp apply_is_never_used_filter(query, %{op: :==, value: v}) when v in [false, "false"] do
    from(k in query, where: not is_nil(k.last_used_at))
  end

  defp apply_is_never_used_filter(query, _), do: query

  defp apply_has_expiry_filters(query, filters) do
    Enum.reduce(filters, query, fn filter, acc -> apply_has_expiry_filter(acc, filter) end)
  end

  defp apply_has_expiry_filter(query, %{op: :==, value: v}) when v in [true, "true"] do
    from(k in query, where: not is_nil(k.expired_at))
  end

  defp apply_has_expiry_filter(query, %{op: :==, value: v}) when v in [false, "false"] do
    from(k in query, where: is_nil(k.expired_at))
  end

  defp apply_has_expiry_filter(query, _), do: query

  # Apply ilike filters for node string fields directly via Ecto, bypassing Flop's add_wildcard.
  defp apply_node_ilike_filters(query, filters) do
    Enum.reduce(filters, query, fn %{field: field, value: value}, acc ->
      from(n in acc, where: ilike(field(n, ^field), ^value))
    end)
  end

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
      {:ok, map} = list_proxy_chain_identifiers("default")
      # map = %{
      #   "abc-123" => %Node{id: "abc-123", ...},
      #   "test" => %Node{id: "abc-123", ...},  # alias
      #   "def-456" => %Node{id: "def-456", ...}
      # }
  """
  @callback list_proxy_chain_identifiers(String.t()) :: {:ok, map()} | {:error, :not_found}
  @spec list_proxy_chain_identifiers(String.t()) :: {:ok, map()} | {:error, :not_found}
  def list_proxy_chain_identifiers(cluster_name) do
    # Single join query: cluster lookup + node fields + alias names in one round trip.
    # Returns only the fields needed for proxy chain auth:
    #   node.id, node.proxy_password, node.http_proxy_port, node.socks5_proxy_port,
    #   cluster.name (for vpn_hostname/1), alias.name (as additional lookup keys).
    rows =
      Repo.all(
        from n in Node,
          join: c in Cluster,
          on: c.id == n.cluster_id,
          left_join: a in Alias,
          on: a.node_id == n.id,
          where: c.name == ^cluster_name,
          select: %{
            id: n.id,
            proxy_password: n.proxy_password,
            http_proxy_port: n.http_proxy_port,
            socks5_proxy_port: n.socks5_proxy_port,
            cluster_name: c.name,
            alias_name: a.name
          }
      )

    # Distinguish between cluster-not-found and cluster-with-no-nodes.
    # The join returns rows only when the cluster exists; an empty result means
    # the cluster name doesn't match any row (i.e. cluster doesn't exist).
    # A cluster with nodes but none matching the identifier is handled upstream.
    case rows do
      [] ->
        # Verify whether the cluster exists at all to return the right error.
        if Repo.exists?(from c in Cluster, where: c.name == ^cluster_name) do
          {:ok, %{}}
        else
          {:error, :not_found}
        end

      _ ->
        identifiers_map =
          Enum.reduce(rows, %{}, fn row, acc ->
            node = %Node{
              id: row.id,
              proxy_password: row.proxy_password,
              http_proxy_port: row.http_proxy_port,
              socks5_proxy_port: row.socks5_proxy_port,
              cluster: %Cluster{name: row.cluster_name}
            }

            acc = Map.put_new(acc, row.id, node)

            case row.alias_name do
              nil -> acc
              name -> Map.put(acc, name, node)
            end
          end)

        {:ok, identifiers_map}
    end
  end

  # ===========================================================================
  # Enrollment Key functions
  # ===========================================================================

  @doc """
  Lists enrollment keys with filtering, sorting, and pagination.

  Supports filtering by:
  - `key` - Exact match or wildcard
  - `uses_remaining` - Exact, `__gte`, `__lte` (null = unlimited)
  - `is_unlimited` - Boolean: true returns unlimited keys (uses_remaining is null)
  - `is_spent` - Boolean: true returns exhausted keys (uses_remaining == 0)
  - `is_expired` - Boolean: true returns expired keys (expired_at in the past)
  - `is_never_used` - Boolean: true returns keys never used (last_used_at is null)
  - `has_expiry` - Boolean: true returns keys with an expiry set (expired_at is not null)
  - `expired_at`, `last_used_at`, `inserted_at`, `updated_at` - Date range (`__gte`, `__lte`)
  - `cluster_name` - Text search with wildcard support (requires join)
  """
  @spec list_enrollment_keys(map()) ::
          {:ok, {[EnrollmentKey.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_enrollment_keys(params \\ %{}) do
    flop_params = RequestParser.parse(params)
    {query, flop_params} = build_enrollment_key_query(flop_params)

    case Flop.validate_and_run(query, flop_params,
           for: EnrollmentKey,
           replace_invalid_params: true
         ) do
      {:ok, {keys, meta}} -> {:ok, {keys, meta}}
      {:error, meta} -> {:error, meta}
    end
  end

  defp build_enrollment_key_query(flop_params) do
    custom_fields = [:cluster_name, :is_unlimited, :is_spent, :is_expired, :is_never_used, :has_expiry]

    {custom, other_filters} =
      Enum.split_with(flop_params[:filters] || [], &(&1.field in custom_fields))

    custom_by_field = Enum.group_by(custom, & &1.field)

    base_query =
      from(k in EnrollmentKey,
        join: c in assoc(k, :cluster),
        preload: [cluster: c]
      )

    query =
      base_query
      |> maybe_apply_filters(custom_by_field[:cluster_name], &apply_cluster_name_filters/2)
      |> maybe_apply_filters(custom_by_field[:is_unlimited], &apply_is_unlimited_filters/2)
      |> maybe_apply_filters(custom_by_field[:is_spent], &apply_is_spent_filters/2)
      |> maybe_apply_filters(custom_by_field[:is_expired], &apply_is_expired_filters/2)
      |> maybe_apply_filters(custom_by_field[:is_never_used], &apply_is_never_used_filters/2)
      |> maybe_apply_filters(custom_by_field[:has_expiry], &apply_has_expiry_filters/2)

    {ilike_filters, flop_params} =
      RequestParser.split_ilike_filters(
        Map.put(flop_params, :filters, other_filters),
        [:key]
      )

    query =
      Enum.reduce(ilike_filters, query, fn %{field: field, value: value}, acc ->
        from(k in acc, where: ilike(field(k, ^field), ^value))
      end)

    {query, flop_params}
  end

  defp maybe_apply_filters(query, nil, _fun), do: query
  defp maybe_apply_filters(query, [], _fun), do: query
  defp maybe_apply_filters(query, filters, fun), do: fun.(query, filters)

  @doc """
  Gets a single enrollment key by ID.
  """
  @spec get_enrollment_key(String.t()) :: {:ok, EnrollmentKey.t()} | {:error, :not_found}
  def get_enrollment_key(id) do
    case Repo.get(EnrollmentKey, id) do
      nil -> {:error, :not_found}
      key -> {:ok, Repo.preload(key, :cluster)}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc """
  Creates an enrollment key for a cluster.

  Generates a base64 JSON blob stored in the `key` column and returned to the
  operator for placement in the agent's ENROLLMENT_KEY env var:

      base64({"admin_urls": [...], "nonce": "<random_32_bytes_base64>"})

  The agent decodes the blob to extract `admin_urls` (for routing) and sends
  the full blob to the verify endpoint. Admin looks up by the blob directly —
  no inner nonce comparison needed.

  The nonce exists solely to make each key unique and unguessable.
  """
  @spec create_enrollment_key(Cluster.t(), map()) ::
          {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  def create_enrollment_key(%Cluster{} = cluster, params \\ %{}) do
    with {:ok, attrs} <- Forms.CreateEnrollmentKeyForm.changeset(params) do
      admin_urls = Application.fetch_env!(:edge_admin, :admin_urls)
      nonce = generate_token()

      key =
        %{"admin_urls" => admin_urls, "nonce" => nonce}
        |> Jason.encode!()
        |> Base.encode64()

      key_attrs =
        attrs
        |> Map.put("key", key)
        |> Map.put("cluster_id", cluster.id)

      case %EnrollmentKey{} |> EnrollmentKey.changeset(key_attrs) |> Repo.insert() do
        {:ok, enrollment_key} -> {:ok, Repo.preload(enrollment_key, :cluster)}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  @doc """
  Updates an enrollment key's `uses_remaining` and/or `expired_at`.

  Only fields explicitly provided are updated. Pass null to unset `expired_at`.
  """
  @spec update_enrollment_key(EnrollmentKey.t(), map()) ::
          {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  def update_enrollment_key(%EnrollmentKey{} = key, params) do
    with {:ok, attrs} <- Forms.UpdateEnrollmentKeyForm.changeset(params) do
      case key |> EnrollmentKey.changeset(attrs) |> Repo.update() do
        {:ok, updated_key} -> {:ok, Repo.preload(updated_key, :cluster)}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  @doc """
  Deletes an enrollment key.
  """
  @spec delete_enrollment_key(EnrollmentKey.t()) ::
          {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  def delete_enrollment_key(%EnrollmentKey{} = key) do
    Repo.delete(key)
  end

  @doc """
  Verifies an enrollment key blob presented by an agent before it joins the VPN.

  The agent sends the full key blob (the base64 JSON string). Admin looks it up
  directly in the DB — no decoding required on the admin side.

  Performs the following checks in order:
  1. Key blob exists in DB
  2. Key is not expired
  3. Key is not spent (uses_remaining == 0; null means unlimited)
  4. Cluster has capacity (NodeLimitCheck)

  On success, atomically decrements `uses_remaining` (unless unlimited) and sets
  `last_used_at`, then fetches the Netmaker default enrollment key for the cluster.

  The decrement uses a conditional UPDATE to prevent race conditions when two agents
  simultaneously attempt to consume the last use of a key.

  Returns a result map always shaped as:
  `%{verified: bool, error: String.t(), netmaker_key: String.t()}`
  """
  @spec verify_enrollment_key(map()) :: {:ok, map()}
  def verify_enrollment_key(params) do
    with {:ok, key_blob} <- Forms.VerifyEnrollmentKeyForm.changeset(params) do
      result =
        case Repo.get_by(EnrollmentKey, key: key_blob) do
          nil ->
            %{verified: false, error: "invalid_key", netmaker_key: ""}

          enrollment_key ->
            enrollment_key = Repo.preload(enrollment_key, :cluster)
            verify_key(enrollment_key)
        end

      {:ok, result}
    end
  end

  defp verify_key(%EnrollmentKey{} = key) do
    cond do
      EnrollmentKey.expired?(key) ->
        %{verified: false, error: "key_expired", netmaker_key: ""}

      EnrollmentKey.spent?(key) ->
        %{verified: false, error: "key_spent", netmaker_key: ""}

      true ->
        case Checks.NodeLimitCheck.check(key.cluster) do
          {:error, _} ->
            %{verified: false, error: "node_limit_reached", netmaker_key: ""}

          :ok ->
            consume_key(key)
        end
    end
  end

  defp consume_key(%EnrollmentKey{} = key) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    # Atomic decrement: only decrements if uses_remaining > 0, skips if nil (unlimited)
    {rows_updated, _} =
      if EnrollmentKey.unlimited?(key) do
        Repo.update_all(
          from(k in EnrollmentKey, where: k.id == ^key.id),
          set: [last_used_at: now]
        )
      else
        Repo.update_all(
          from(k in EnrollmentKey, where: k.id == ^key.id and k.uses_remaining > 0),
          inc: [uses_remaining: -1],
          set: [last_used_at: now]
        )
      end

    if rows_updated == 0 do
      # Another agent consumed the last use between our read and this update
      %{verified: false, error: "key_spent", netmaker_key: ""}
    else
      network_name = node_network_name(key.cluster)

      netmaker_key =
        case Vpn.get_default_enrollment_key(network_name) do
          {:ok, token} -> token
          {:error, _} -> ""
        end

      %{verified: true, error: "", netmaker_key: netmaker_key}
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
      ghost_networks_deleted: 0,
      aliases_cleaned: 0,
      ghost_aliases_cleaned: 0,
      errors: 0
    })
  end

  @doc """
  Reconciles a single cluster's state between the DB and Netmaker.

  Called by ReconcileClusterWorker — one job per cluster, allowing independent
  retries and parallel processing. Performs the same steps as reconcile_clusters/0
  but scoped to a single cluster struct.
  """
  @spec reconcile_cluster(Cluster.t()) :: map()
  def reconcile_cluster(%Cluster{} = cluster) do
    acc = %{
      clusters_processed: 0,
      nodes_added: 0,
      nodes_removed: 0,
      nodes_deleted: 0,
      clusters_deleted: 0,
      ghost_networks_deleted: 0,
      aliases_cleaned: 0,
      ghost_aliases_cleaned: 0,
      errors: 0
    }

    db_nodes = Repo.all(from(n in Node, where: n.cluster_id == ^cluster.id, preload: [:cluster]))

    result = reconcile_single_cluster(cluster, db_nodes, acc)
    result = cleanup_orphaned_clusters([cluster], result)
    cleanup_ghost_aliases([cluster], result)
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
        # All pages processed — run the Netmaker→DB ghost network sweep once at the end
        final_result = cleanup_ghost_networks(result_with_ghost_aliases)
        Logger.info("Cluster reconciliation completed: #{inspect(final_result)}")
        final_result
      end
    end
  end

  defp reconcile_single_cluster(cluster, db_nodes, acc) do
    network_name = node_network_name(cluster)

    Logger.debug("Reconciling cluster #{cluster.name} (network: #{network_name})")

    expected_host_ids = MapSet.new(db_nodes, & &1.netmaker_host_id)

    case Vpn.list_nodes(network_name) do
      {:ok, netmaker_nodes} ->
        actual_host_ids =
          netmaker_nodes
          |> Enum.map(& &1["hostid"])
          |> Enum.reject(&is_nil/1)
          |> MapSet.new()

        counts = reconcile_cluster_nodes(cluster, db_nodes, netmaker_nodes, expected_host_ids, actual_host_ids)

        %{
          clusters_processed: acc.clusters_processed + 1,
          nodes_added: acc.nodes_added + counts.added,
          nodes_removed: acc.nodes_removed + counts.removed,
          nodes_deleted: acc.nodes_deleted + counts.deleted,
          clusters_deleted: acc.clusters_deleted,
          aliases_cleaned: acc.aliases_cleaned + counts.aliases_cleaned,
          ghost_aliases_cleaned: acc.ghost_aliases_cleaned,
          errors: acc.errors
        }

      {:error, reason} ->
        Logger.error("Failed to list nodes for cluster #{cluster.name}: #{inspect(reason)}")
        %{acc | errors: acc.errors + 1}
    end
  end

  defp reconcile_cluster_nodes(cluster, db_nodes, _netmaker_nodes, expected_host_ids, actual_host_ids) do
    orphaned_in_db = MapSet.difference(expected_host_ids, actual_host_ids)
    orphaned_nodes = Enum.filter(db_nodes, fn node -> node.netmaker_host_id in orphaned_in_db end)

    aliases_cleaned = cleanup_orphaned_aliases(orphaned_nodes)
    {deleted, unenrolled_host_ids} = delete_orphaned_nodes(orphaned_nodes)
    added = add_missing_nodes(unenrolled_host_ids, node_network_name(cluster), cluster.name)

    extra_in_netmaker = MapSet.difference(actual_host_ids, expected_host_ids)

    all_db_host_ids =
      from(n in Node, select: n.netmaker_host_id)
      |> Repo.all()
      |> MapSet.new()

    managed_extra = MapSet.intersection(extra_in_netmaker, all_db_host_ids)
    unmanaged_extra = MapSet.difference(extra_in_netmaker, all_db_host_ids)

    removed = remove_extra_nodes(managed_extra, node_network_name(cluster), cluster.name)

    evicted =
      if Application.get_env(:edge_admin, :evict_rogue_hosts, true) do
        # Build hostname map from actual host objects (hosts have "name"; node objects do not)
        host_hostname_map =
          case Vpn.list_hosts(node_network_name(cluster)) do
            {:ok, hosts} -> Map.new(hosts, fn h -> {h["id"], h["name"] || ""} end)
            {:error, _} -> %{}
          end

        evict_rogue_hosts(unmanaged_extra, host_hostname_map, node_network_name(cluster), cluster.name)
      else
        if not MapSet.equal?(unmanaged_extra, MapSet.new()) do
          Logger.info(
            "Reconciliation: #{MapSet.size(unmanaged_extra)} unrecognized host(s) in #{node_network_name(cluster)} — eviction disabled (EVICT_ROGUE_HOSTS=false)"
          )
        end

        0
      end

    %{
      added: added,
      removed: removed,
      deleted: deleted + evicted,
      aliases_cleaned: aliases_cleaned
    }
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

  defp evict_rogue_hosts(host_ids, host_hostname_map, network_name, cluster_name) do
    Enum.reduce(host_ids, 0, fn host_id, count ->
      hostname = Map.get(host_hostname_map, host_id, "")

      if String.starts_with?(hostname, "admin-") do
        # Admin nodes are handled by the zombie admin cleaner - never touch them
        Logger.debug(
          "Reconciliation: Skipping admin host #{host_id} (#{hostname}) in network #{network_name} - handled by zombie cleaner"
        )

        count
      else
        case Vpn.delete_host(host_id) do
          {:ok, _} ->
            Logger.info(
              "Reconciliation: Evicted rogue host #{host_id} (#{hostname}) from network #{network_name} (cluster: #{cluster_name})"
            )

            count + 1

          {:error, :not_found} ->
            Logger.debug("Reconciliation: Rogue host #{host_id} already gone from network #{network_name}")
            count

          {:error, reason} ->
            Logger.warning(
              "Reconciliation: Failed to evict rogue host #{host_id} (#{hostname}) from network #{network_name}: #{inspect(reason)}"
            )

            count
        end
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

  # Returns {deleted_count, unenrolled_host_ids} where unenrolled_host_ids is a MapSet
  # of host ID strings confirmed to exist in Netmaker but not enrolled in this network.
  # These are passed to add_missing_nodes to re-enroll them.
  # Host IDs deleted from DB (host gone from Netmaker entirely) are excluded
  # so add_missing_nodes never calls add_host_to_network on non-existent hosts.
  defp delete_orphaned_nodes(orphaned_nodes) do
    Enum.reduce(orphaned_nodes, {0, MapSet.new()}, fn node, {count, unenrolled_ids} ->
      # Check if host exists in Netmaker at all
      case Vpn.get_host(node.netmaker_host_id) do
        {:ok, _host} ->
          # Host exists in Netmaker but is not enrolled in this network.
          # Don't delete from DB - add_missing_nodes will re-enroll it.
          Logger.debug(
            "Reconciliation: Host #{node.netmaker_host_id} exists in Netmaker but is not enrolled in this network, skipping DB deletion"
          )

          {count, MapSet.put(unenrolled_ids, node.netmaker_host_id)}

        {:error, :not_found} ->
          # Host doesn't exist in Netmaker at all - safe to delete from DB.
          # This means deletion was attempted and Netmaker succeeded but DB failed.
          Logger.info("Reconciliation: Deleting orphaned node #{node.id} from DB (host not found in Netmaker)")

          case Repo.delete(node) do
            {:ok, _} ->
              broadcast_metadata_event({:node_deleted, node.id, node.cluster_id})
              {count + 1, unenrolled_ids}

            {:error, changeset} ->
              Logger.error("Reconciliation: Failed to delete orphaned node #{node.id}: #{inspect(changeset)}")
              {count, unenrolled_ids}
          end

        {:error, reason} ->
          Logger.warning("Reconciliation: Failed to check if host #{node.netmaker_host_id} exists: #{inspect(reason)}")
          {count, unenrolled_ids}
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

  # Cleans up ghost networks: Netmaker has a "cluster-*" network that has no matching
  # DB cluster record. This is the failure path for Netmaker-first cluster create —
  # Netmaker succeeded but our DB insert failed.
  #
  # Safety contract: we only ever touch networks with the "cluster-" prefix. Networks
  # with "admin-cluster-" prefix are admin infrastructure and must never be touched here.
  defp cleanup_ghost_networks(acc) do
    case Vpn.list_networks() do
      {:ok, netmaker_networks} ->
        # All "cluster-*" networks in Netmaker (excludes "admin-cluster-*" by prefix check)
        netmaker_cluster_names =
          netmaker_networks
          |> Enum.map(& &1["netid"])
          |> Enum.filter(&String.starts_with?(&1, "cluster-"))
          |> MapSet.new()

        # All expected network names from our DB
        db_network_names =
          from(c in Cluster, select: c.name)
          |> Repo.all()
          |> MapSet.new(&node_network_name/1)

        ghost_network_names = MapSet.difference(netmaker_cluster_names, db_network_names)

        deleted =
          Enum.reduce(ghost_network_names, 0, fn network_name, count ->
            case Vpn.delete_network(network_name) do
              {:ok, _} ->
                Logger.info("Reconciliation: Deleted ghost Netmaker network #{network_name} (no matching DB cluster)")
                count + 1

              {:error, :not_found} ->
                # Already gone
                count

              {:error, reason} ->
                Logger.warning("Reconciliation: Failed to delete ghost network #{network_name}: #{inspect(reason)}")
                count
            end
          end)

        %{acc | ghost_networks_deleted: acc.ghost_networks_deleted + deleted}

      {:error, reason} ->
        Logger.warning("Reconciliation: Failed to list Netmaker networks for ghost cleanup: #{inspect(reason)}")
        %{acc | errors: acc.errors + 1}
    end
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
    vpn_hostname = Alias.vpn_hostname(alias_record)
    netmaker_dns_name = Alias.netmaker_dns_name(alias_record)

    # 1. Try to delete DNS entry (best-effort)
    case Vpn.delete_dns_entry(network_name, netmaker_dns_name) do
      {:ok, _} ->
        Logger.info("Deleted DNS entry for alias #{alias_record.name}: #{vpn_hostname}")

      {:error, :not_found} ->
        Logger.debug("DNS entry already deleted for alias #{alias_record.name}: #{vpn_hostname}")

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
  - `node_id` - Exact match by node UUID
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

    {ilike_filters, flop_params} =
      RequestParser.split_ilike_filters(
        Map.put(flop_params, :filters, other_filters),
        [:name]
      )

    query_with_ilike =
      Enum.reduce(ilike_filters, query_with_cluster_filter, fn %{field: field, value: value}, acc ->
        from(a in acc, where: ilike(field(a, ^field), ^value))
      end)

    # Run Flop query
    case Flop.validate_and_run(query_with_ilike, flop_params,
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
    with {:ok, attrs} <- Forms.CreateAliasForm.changeset(params) do
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
              vpn_hostname = Alias.vpn_hostname(alias_record)
              netmaker_dns_name = Alias.netmaker_dns_name(alias_record)

              case Vpn.create_dns_entry(network_name, %{
                     name: netmaker_dns_name,
                     address: ip_address
                   }) do
                {:ok, _} ->
                  Logger.info("Created DNS entry for alias #{alias_record.name}: #{vpn_hostname} -> #{ip_address}")
                  {:ok, alias_record}

                {:error, :service_unavailable} = error ->
                  # Netmaker DNS creation failed - rollback DB insert
                  Logger.warning("Netmaker DNS creation failed, rolling back DB alias: #{alias_record.name}")
                  Repo.delete(alias_record)
                  error
              end

            {:error, changeset} ->
              Repo.normalize_conflict({:error, changeset}, [:name, :cluster_id])
          end

        {:ok, _node} ->
          # Node exists in Netmaker but has no IP yet — still enrolling
          Logger.warning(
            "Cannot create alias: node #{node.netmaker_host_id} has no IP address yet in network #{network_name}"
          )

          {:error, {:conflict, "Node has not been assigned an IP address yet. It may still be enrolling in the VPN."}}

        {:error, :not_found} ->
          # Node is not enrolled in this network at all
          Logger.warning(
            "Cannot create alias: node #{node.netmaker_host_id} is not enrolled in network #{network_name}"
          )

          {:error,
           {:conflict,
            "Node is not enrolled in the VPN network. Ensure the agent is connected and has joined the network."}}

        {:error, :service_unavailable} ->
          Logger.error("Failed to query Netmaker nodes for network #{network_name}")
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
    vpn_hostname = Alias.vpn_hostname(alias_record)
    netmaker_dns_name = Alias.netmaker_dns_name(alias_record)

    # 1. Delete DNS entry from Netmaker FIRST
    case Vpn.delete_dns_entry(network_name, netmaker_dns_name) do
      {:ok, _} ->
        Logger.info("Deleted DNS entry for alias #{alias_record.name}: #{vpn_hostname}")
        delete_alias_from_db(alias_record)

      {:error, :not_found} ->
        # DNS already gone - continue with DB deletion
        Logger.info("DNS entry already deleted for alias #{alias_record.name}: #{vpn_hostname}")
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
  Cleans up ghost aliases in both directions for each cluster:

  Direction 1 — DB → Netmaker:
    Aliases in DB whose DNS entry no longer exists in Netmaker.
    (DNS was deleted first per our flow, DB cleanup failed.)
    Fix: delete the DB record.

  Direction 2 — Netmaker → DB:
    Custom DNS entries in Netmaker with no matching DB alias.
    This is the common failure path: node deleted (or cluster changed),
    cleanup_node_aliases failed to reach Netmaker (service unavailable),
    DB alias was deleted by cascade, DNS entry orphaned in Netmaker.
    Fix: delete the DNS entry from Netmaker.
  """
  @spec cleanup_ghost_aliases([Cluster.t()], map()) :: map()
  def cleanup_ghost_aliases(clusters, acc) do
    Enum.reduce(clusters, acc, fn cluster, result ->
      network_name = node_network_name(cluster)

      case Vpn.list_custom_dns_entries(network_name) do
        {:ok, netmaker_custom_entries} ->
          db_aliases = Repo.all(from(a in Alias, where: a.cluster_id == ^cluster.id, preload: [:cluster]))

          netmaker_dns_names = MapSet.new(netmaker_custom_entries, & &1["name"])
          db_alias_hostnames = MapSet.new(db_aliases, &Alias.vpn_hostname/1)
          db_alias_short_names = MapSet.new(db_aliases, &Alias.netmaker_dns_name/1)

          db_deleted = delete_ghost_db_aliases(db_aliases, netmaker_dns_names)

          dns_deleted =
            delete_orphaned_dns_entries(netmaker_custom_entries, network_name, db_alias_short_names, db_alias_hostnames)

          total_cleaned = db_deleted + dns_deleted

          if total_cleaned > 0 do
            Logger.info(
              "Reconciliation: Cleaned #{total_cleaned} ghost alias(es) in cluster #{cluster.name} " <>
                "(#{db_deleted} DB records, #{dns_deleted} DNS entries)"
            )
          end

          %{result | ghost_aliases_cleaned: result.ghost_aliases_cleaned + total_cleaned}

        {:error, reason} ->
          Logger.warning("Reconciliation: Failed to list DNS entries for cluster #{cluster.name}: #{inspect(reason)}")
          %{result | errors: result.errors + 1}
      end
    end)
  end

  # Direction 1: DB aliases whose DNS is gone from Netmaker → delete the DB record.
  # Handles the case where Netmaker-first deletion succeeded but DB deletion failed.
  defp delete_ghost_db_aliases(db_aliases, netmaker_dns_names) do
    Enum.reduce(db_aliases, 0, fn alias_record, count ->
      if MapSet.member?(netmaker_dns_names, Alias.vpn_hostname(alias_record)) do
        count
      else
        case Repo.delete(alias_record) do
          {:ok, _} ->
            Logger.info("Reconciliation: Deleted ghost alias #{alias_record.name} from DB (DNS gone from Netmaker)")
            count + 1

          {:error, changeset} ->
            Logger.error("Reconciliation: Failed to delete ghost DB alias #{alias_record.name}: #{inspect(changeset)}")
            count
        end
      end
    end)
  end

  # Direction 2: Netmaker custom DNS entries with no DB alias → delete the DNS entry.
  # Handles the case where cleanup_node_aliases couldn't reach Netmaker (service unavailable)
  # so the DB alias was deleted (cascade) but the DNS entry was orphaned in Netmaker.
  # Netmaker returns names with domain suffix appended — strip it to get the stored short name
  # for the delete call.
  defp delete_orphaned_dns_entries(netmaker_custom_entries, network_name, db_alias_short_names, db_alias_hostnames) do
    default_domain = Vpn.default_domain()

    Enum.reduce(netmaker_custom_entries, 0, fn entry, count ->
      dns_name = entry["name"]

      short_name =
        case default_domain do
          "" -> dns_name
          domain -> String.replace_suffix(dns_name, ".#{domain}", "")
        end

      if MapSet.member?(db_alias_short_names, short_name) or MapSet.member?(db_alias_hostnames, dns_name) do
        count
      else
        case Vpn.delete_dns_entry(network_name, short_name) do
          {:ok, _} ->
            Logger.info("Reconciliation: Deleted orphaned DNS entry #{dns_name} from Netmaker (no DB alias)")
            count + 1

          {:error, :not_found} ->
            Logger.debug("Reconciliation: DNS entry #{dns_name} already gone from Netmaker")
            count

          {:error, reason} ->
            Logger.warning("Reconciliation: Failed to delete orphaned DNS entry #{dns_name}: #{inspect(reason)}")
            count
        end
      end
    end)
  end
end
