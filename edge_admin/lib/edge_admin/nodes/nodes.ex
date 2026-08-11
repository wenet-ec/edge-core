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

  Two sources of state must be kept in sync: the Admin database and Netmaker (the VPN
  provider). There is no transaction spanning both — every operation that touches both
  systems has a partial-failure window. Cluster reconciliation is what heals drift.
  Understand it before changing any
  create/delete ordering here.

  ### Ordering rules (why they are what they are)

  **Cluster create — DB first, then Netmaker:**
  Netmaker is the authority on IP space (it sees `admin-cluster-*` networks our DB
  doesn't). To make DB-first safe, `create_cluster/1` fetches all Netmaker ranges
  via `Vpn.list_network_ranges/0` up front and merges them with the DB range list
  before running `SubnetOverlapCheck` and `Vpn.generate_next_subnet/1`. The fetch
  doubles as a liveness probe — if Netmaker is unreachable, we fail fast with
  `:service_unavailable` and never touch the DB. If Netmaker rejects the create
  anyway (race with a concurrent admin or admin-mesh write), we rollback the DB
  insert. A DB insert failure with no Netmaker call leaves no state to clean.

  **Cluster delete — retire in DB, then delete from Netmaker:**
  `deleted_at` is the durable canonical decision that the cluster no longer exists for
  public reads or new membership. `DeleteClusterWorker` deletes the Netmaker network
  after that transaction commits and finally removes the tombstone after verifying the
  network is absent. This avoids holding a database transaction across external IO.

  **Alias create — read IP from Netmaker, then DB, then write DNS to Netmaker:**
  The node's VPN IP is only known to Netmaker; we must fetch it. The DB insert anchors
  the alias record. The DNS write is the final step. If DNS write fails, we rollback the
  DB insert. If rollback also fails, `cleanup_ghost_aliases/2` in the reconciler will
  recreate the missing DNS entry from DB. Ghost DNS entries (DNS in Netmaker, no DB
  record) are cleaned by the Netmaker→DB direction of `cleanup_ghost_aliases/2`.

  **Alias delete — Netmaker first, then DB:**
  A missing DNS entry is harmless because the DB row still makes the alias repairable.

  ### Reconciler directions (both are needed)

  `ensure_cluster_network/1` — active DB cluster has no Netmaker network:
  Recreates the network from the cluster's immutable DB configuration. A retired
  cluster is never repaired here; its deletion worker owns its network instead.

  `cleanup_ghost_networks/1` — Netmaker has `cluster-*` network, DB doesn't:
  Deletes the unowned network. Safety: we only touch networks with the `cluster-`
  prefix — `admin-cluster-*` networks are admin infrastructure and are never touched
  here. The prefix contract is enforced by `Vpn.build_network_name/2`.

  `cleanup_ghost_aliases/2` — reconciles alias DNS from DB to Netmaker, repairs stale
  IPs, and deletes Netmaker DNS entries with no matching DB alias.

  ### Subnet pool and scale

  IPv4 cluster subnets are carved from `CLUSTER_AUTO_GENERATED_V4_RANGES` (default: CGNAT
  `100.64.0.0/10`) at `CLUSTER_V4_SUBNET_PREFIX` (default: `/24`). This gives a hard cap
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
    re-enrolls and gets a new IP, the reconciler repairs alias DNS by deleting and
    recreating the Netmaker DNS entry with the current IP.

  - `cleanup_ghost_networks/1` deletes by prefix convention, not by any Netmaker-side
    ownership marker. If something outside this system ever creates a `cluster-*` network
    in Netmaker, the reconciler will delete it. The prefix contract must be maintained.

  - `cleanup_ghost_networks/1` runs once per scheduled maintenance sweep. A ghost
    network created during that sweep may not be cleaned until the next run. This is
    acceptable — ghost networks are harmless, just wasteful.

  - `reconcile_cluster/1` does NOT run `cleanup_ghost_networks/1`. It only has context
    for one cluster, not the global Netmaker state. The maintenance scheduler performs
    the global sweep once after it queues per-cluster work.

  ## Examples

      # List all nodes with filtering and pagination
      iex> list_nodes(%{"cluster_name" => "prod", "status" => "healthy"})
      {:ok, {[%Node{}, ...], %Flop.Meta{}}}

      # Get a single node by ID
      iex> get_node("abc-123")
      {:ok, %Node{id: "abc-123", cluster: %Cluster{}, ...}}

      # Register or update a node from agent
      iex> register_node(%{"node_id" => "abc-123", "network_name" => "cluster-test", ...})
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
  alias EdgeAdmin.Admins.Metadata
  alias EdgeAdmin.Commands
  alias EdgeAdmin.Events
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Nodes.Checks
  alias EdgeAdmin.Nodes.Filters.ClusterFilters
  alias EdgeAdmin.Nodes.Filters.NodeFilters
  alias EdgeAdmin.Nodes.Forms
  alias EdgeAdmin.Nodes.Persistence
  alias EdgeAdmin.Nodes.Queries.ClusterQueries
  alias EdgeAdmin.Nodes.Resources.Aliases
  alias EdgeAdmin.Nodes.Resources.Diagnostics
  alias EdgeAdmin.Nodes.Resources.EnrollmentKeys
  alias EdgeAdmin.Nodes.Schemas.Alias
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Schemas.NodeDiagnostic
  alias EdgeAdmin.Nodes.Workers.DeleteClusterWorker
  alias EdgeAdmin.Nodes.Workflows.HealthCheck
  alias EdgeAdmin.Nodes.Workflows.Reconciliation
  alias EdgeAdmin.Nodes.Workflows.Registration
  alias EdgeAdmin.Random
  alias EdgeAdmin.Repo
  alias EdgeAdmin.RequestParser
  alias EdgeAdmin.Vpn

  require Logger

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  # ===========================================================================
  # Cluster functions
  # ===========================================================================
  @doc """
  Lists all clusters with node counts, filtering, and pagination.

  Retired clusters are not returned.

  Supports filtering by:
  - `name` - Exact match or wildcard (`prod*`, `*tion`, `*rod*`)
  - `name__in` - Exact IN match on cluster names — comma-separated list
  - `ipv4_range` - Text search (supports wildcards)
  - `ipv6_range` - Text search (supports wildcards)
  - `node_limit` - Exact, `__gte`, `__lte` (null = no limit)
  - `has_node_limit` - Boolean: true returns clusters with a node limit set
  - `node_id__in` - Exact IN match on node IDs — returns clusters that contain any of those nodes
  - `inserted_at__gte/lte` - Date range filter
  - `updated_at__gte/lte` - Date range filter
  - `node_count` - Range queries (e.g., `node_count__gte=5`, `node_count__lte=10`) — virtual filter computed via join

  Supports sorting by:
  - `name`, `ipv4_range`, `ipv6_range`, `inserted_at`, `updated_at`
  - Default: `inserted_at:desc`

  ## Parameters
  - `params` - Map of filter/sort/pagination parameters (Flop format)

  ## Returns
  - `{:ok, {clusters, meta}}` - List of clusters with pagination metadata
  - `{:error, meta}` - Validation errors

  ## Examples

      iex> list_clusters(%{"name" => "prod*"})
      {:ok, {[%Cluster{name: "production"}], %Flop.Meta{}}}

      iex> list_clusters(%{"node_count__gte" => "5"})
      {:ok, {[%Cluster{nodes: [...]}, ...], %Flop.Meta{}}}
  """
  @spec list_clusters(map()) :: {:ok, {[Cluster.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_clusters(params \\ %{}), do: run_cluster_list_query(ClusterQueries.active(), params)

  @doc "Lists active and retired clusters for maintenance reconciliation."
  @spec list_clusters_for_reconciliation(map()) ::
          {:ok, {[Cluster.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_clusters_for_reconciliation(params), do: run_cluster_list_query(Cluster, params)

  defp run_cluster_list_query(cluster_query, params) do
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

    {node_ids_filters, other_filters} =
      Enum.split_with(other_filters, fn filter -> filter.field == :node_id end)

    # Extract ilike filters for string fields — Flop's :ilike wraps values in %..%
    # and escapes any existing % characters, breaking wildcard patterns like "def%".
    # Apply these as raw Ecto ilike/2 clauses instead.
    {ilike_filters, flop_params} =
      RequestParser.split_ilike_filters(
        Map.put(flop_params, :filters, other_filters),
        [:name, :ipv4_range, :ipv6_range]
      )

    # Build base query with node_count if filtering/sorting on it
    base_query =
      if node_count_filters == [] do
        cluster_query
      else
        ClusterFilters.apply_node_count(
          from(c in cluster_query,
            left_join: n in assoc(c, :nodes),
            group_by: c.id,
            select_merge: %{node_count: count(n.id)}
          ),
          node_count_filters
        )
      end

    base_query =
      base_query
      |> ClusterFilters.apply_has_node_limit(has_node_limit_filters)
      |> ClusterFilters.apply_node_ids_on_clusters(node_ids_filters)
      |> ClusterFilters.apply_ilike(ilike_filters)

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

  @doc """
  Lists cluster-node mappings.

  ## Options
  - `:prefix` - Add DNS name prefixes (default: false)
    - `true`: Returns "cluster-prod", "node-abc123" (for metadata)
    - `false`: Returns "prod", "abc123" (for discovery endpoints)
  - `:filter_status` - Filter nodes by status (default: nil, includes all)
    - Example: `[:healthy, :unhealthy]` excludes unreachable nodes

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
      from(c in ClusterQueries.active(),
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
          id -> if use_prefix, do: Node.node_name(id), else: id
        end
      end
    )
    |> Enum.map(fn {cluster_name, node_ids} ->
      %{
        name: if(use_prefix, do: Cluster.network_name(cluster_name), else: cluster_name),
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
    case Repo.one(ClusterQueries.active_by_name(name)) do
      nil -> {:error, :not_found}
      cluster -> {:ok, Repo.preload(cluster, :nodes)}
    end
  end

  @doc """
  Creates a cluster and its Netmaker network.

  Flow:
  1. Validate input
  2. Fetch every IPv4 and IPv6 range Netmaker currently knows about (acts as both a
     liveness probe and the authoritative overlap set — local DB only tracks
     `cluster-*` ranges, not admin-mesh networks)
  3. Merge with DB ranges, then validate or auto-generate both address families
  4. Create DB record (validates uniqueness constraints)
  5. Create Netmaker network (rollback DB on failure)
  6. Emit event for metadata recomputation

  If Netmaker is unreachable, returns service unavailable immediately (no DB call).
  If DB creation fails, returns validation error immediately (no Netmaker call).
  If Netmaker creation fails, deletes DB record and returns service unavailable.

  A later missing network does not make the active DB cluster disposable: the active
  row is the desired configuration, so reconciliation recreates the network from it.

  Returns `{:ok, cluster}`, `{:error, changeset}` (validation), `{:error, {:conflict, reason}}` (CIDR overlap), or `{:error, :service_unavailable}` (health check or Netmaker failure).
  """
  @spec create_cluster(map()) ::
          {:ok, Cluster.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:conflict, String.t()}}
          | {:error, :service_unavailable}
  def create_cluster(attrs \\ %{}) do
    with {:ok, validated_attrs} <- Forms.CreateClusterForm.changeset(attrs),
         {:ok, existing_ranges} <- existing_cluster_ranges(),
         {:ok, ranges} <- resolve_cluster_ranges(validated_attrs, existing_ranges),
         {:ok, cluster} <- insert_cluster(validated_attrs, ranges) do
      provision_cluster_network(cluster)
    end
  end

  defp existing_cluster_ranges do
    with {:ok, netmaker_ranges} <- Vpn.list_network_ranges() do
      # Retired clusters retain their ranges until their network cleanup finishes.
      {:ok,
       %{
         ipv4: Enum.uniq(Repo.all(from(c in Cluster, select: c.ipv4_range)) ++ netmaker_ranges.ipv4),
         ipv6: Enum.uniq(Repo.all(from(c in Cluster, select: c.ipv6_range)) ++ netmaker_ranges.ipv6)
       }}
    end
  end

  defp resolve_cluster_ranges(attrs, existing_ranges) do
    with :ok <- Checks.SubnetOverlapCheck.check(attrs["ipv4_range"], existing_ranges.ipv4),
         :ok <- Checks.SubnetOverlapCheck.check_ipv6(attrs["ipv6_range"], existing_ranges.ipv6),
         {:ok, ipv4_range} <- allocate_ipv4_range(attrs["ipv4_range"], existing_ranges.ipv4),
         {:ok, ipv6_range} <- allocate_ipv6_range(attrs["ipv6_range"], existing_ranges.ipv6) do
      {:ok, %{ipv4: ipv4_range, ipv6: ipv6_range}}
    end
  end

  defp insert_cluster(attrs, %{ipv4: ipv4_range, ipv6: ipv6_range}) do
    attrs
    |> Map.put("ipv4_range", ipv4_range)
    |> Map.put("ipv6_range", ipv6_range)
    |> then(&Cluster.changeset(%Cluster{}, &1))
    |> Repo.insert()
    |> Repo.normalize_conflict([:name, :ipv4_range, :ipv6_range])
  end

  defp provision_cluster_network(cluster) do
    network_name = Cluster.network_name(cluster)
    opts = %{addressrange: cluster.ipv4_range, addressrange6: cluster.ipv6_range}

    case Vpn.create_network(network_name, opts) do
      {:ok, _} ->
        Logger.info("Created Netmaker network: #{network_name}")
        Metadata.Events.publish(:cluster_created)
        {:ok, cluster}

      {:error, :already_exists} ->
        resolve_existing_network(cluster, network_name)

      {:error, :service_unavailable} = error ->
        Logger.warning("Netmaker network creation failed, rolling back DB cluster: #{cluster.name}")
        Repo.delete(cluster)
        error
    end
  end

  defp resolve_existing_network(cluster, network_name) do
    with {:ok, %{"addressrange" => ipv4_range, "addressrange6" => ipv6_range}} <- Vpn.get_network(network_name),
         true <- ipv4_range == cluster.ipv4_range and ipv6_range == cluster.ipv6_range do
      Logger.info("Netmaker network #{network_name} already exists with matching dual-stack ranges")
      Metadata.Events.publish(:cluster_created)
      {:ok, cluster}
    else
      {:ok, _network} ->
        Repo.delete(cluster)
        {:error, {:conflict, "Netmaker network #{network_name} exists with different immutable address ranges"}}

      {:error, _} = error ->
        Repo.delete(cluster)
        error

      false ->
        Repo.delete(cluster)
        {:error, {:conflict, "Netmaker network #{network_name} exists with different immutable address ranges"}}
    end
  end

  defp allocate_ipv4_range(nil, existing_ranges), do: Vpn.generate_next_subnet(existing_ranges)
  defp allocate_ipv4_range(range, _existing_ranges), do: {:ok, range}

  defp allocate_ipv6_range(nil, existing_ranges), do: Vpn.generate_next_ipv6_subnet(existing_ranges)
  defp allocate_ipv6_range(range, _existing_ranges), do: {:ok, range}

  @doc """
  Updates a cluster.

  `node_limit` is an Edge Admin policy and is intentionally not sent to Netmaker.
  Netmaker's network membership includes both Admin and Agent hosts, so its own
  network-level limit would not represent this cluster's edge-node limit.
  The active cluster row is re-read and locked before the limit is checked or updated.

  ## Parameters
  - `cluster` - The cluster struct to update
  - `params` - Raw request params (validated through UpdateClusterForm)

  ## Returns
  - `{:ok, cluster}` - Update succeeded
  - `{:error, :not_found}` - Cluster was retired or no longer exists
  - `{:error, changeset}` - Validation failed
  """
  @spec update_cluster(Cluster.t(), map()) ::
          {:ok, Cluster.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_cluster(%Cluster{} = cluster, params) do
    with {:ok, attrs} <- Forms.UpdateClusterForm.changeset(params) do
      update_active_cluster(cluster.name, attrs)
    end
  end

  defp update_active_cluster(cluster_name, attrs) do
    fn ->
      with %Cluster{} = cluster <- Persistence.lock_active_cluster(cluster_name),
           :ok <- Checks.NodeLimitBelowCountCheck.check(cluster, Map.get(attrs, "node_limit")),
           {:ok, updated_cluster} <-
             cluster
             |> Cluster.changeset(attrs)
             |> Repo.update() do
        updated_cluster
      else
        nil -> Repo.rollback(:not_found)
        {:error, _} = error -> Repo.rollback(error)
      end
    end
    |> Repo.transaction_with_write_lock()
    |> case do
      {:ok, cluster} -> {:ok, Repo.preload(cluster, :nodes)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retires an empty cluster from the public API and enqueues Netmaker cleanup.

  The retirement transaction locks the active cluster, rechecks that it is empty, writes
  `deleted_at`, and inserts the deletion job atomically. New registration and
  cluster-move paths use the same short transaction boundary, so they cannot enter a
  cluster after retirement wins. Netmaker deletion happens asynchronously after commit.

  Returns `{:ok, cluster}`, `{:error, :not_found}`, or
  `{:error, {:conflict, reason}}` when the cluster has nodes.
  """
  @spec delete_cluster(Cluster.t()) ::
          {:ok, Cluster.t()}
          | {:error, :not_found}
          | {:error, {:conflict, String.t()}}
          | {:error, :service_unavailable}
  def delete_cluster(%Cluster{} = cluster) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    fn ->
      with %Cluster{} = active_cluster <- Persistence.lock_active_cluster(cluster.name),
           :ok <- Checks.ClusterNotEmptyCheck.check(active_cluster),
           # ===========================================================================
           # Node functions
           # ===========================================================================
           {:ok, retired_cluster} <-
             active_cluster
             |> Ecto.Changeset.change(deleted_at: now)
             |> Repo.update(),
           {:ok, _job} <-
             %{
               "cluster_name" => retired_cluster.name,
               "cluster_id" => retired_cluster.id
             }
             |> DeleteClusterWorker.new()
             |> Oban.insert() do
        retired_cluster
      else
        nil -> Repo.rollback(:not_found)
        {:error, _} = error -> Repo.rollback(error)
      end
    end
    |> Repo.transaction_with_write_lock()
    |> case do
      {:ok, retired_cluster} ->
        Metadata.Events.publish(:cluster_deleted)
        {:ok, retired_cluster}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, {:conflict, _} = error} ->
        error

      {:error, reason} ->
        Logger.error("Failed to retire cluster #{cluster.name}: #{inspect(reason)}")
        {:error, :service_unavailable}
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
      {:ok, %Node{status: :unhealthy}}
  """
  @spec update_node(Node.t(), map()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()}
  def update_node(%Node{} = node, attrs) do
    node
    |> Node.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates or replaces a node's one-use recovery key.

  The returned value is the complete base64 JSON blob the operator supplies to
  a fresh Agent as `RECOVERY_KEY` alongside its normal enrollment key.
  """
  @spec create_node_recovery_key(Node.t()) :: {:ok, String.t()} | {:error, Ecto.Changeset.t()}
  def create_node_recovery_key(%Node{} = node) do
    node = Repo.preload(node, :cluster)

    recovery_key =
      %{"node_id" => node.id, "cluster_name" => node.cluster.name, "nonce" => Random.token()}
      |> JSON.encode!()
      |> Base.encode64()

    case update_node(node, %{recovery_key: recovery_key}) do
      {:ok, _node} -> {:ok, recovery_key}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Deletes a node's active recovery key.
  """
  @spec delete_node_recovery_key(Node.t()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()}
  def delete_node_recovery_key(%Node{} = node), do: update_node(node, %{recovery_key: nil})

  @doc """
  Changes a node's cluster.

  DB-first approach: Updates database immediately, then best-effort syncs with Netmaker.
  A background reconciliation worker handles any inconsistencies.

  Flow:
  1. Serialize the target-cluster admission and update the database (source of truth)
  2. Clear the recovery key and delete all aliases (they're cluster-specific)
  3. Best-effort sync: Add host to new network
  4. Best-effort sync: Remove host from old network
  5. Emit event for metadata recomputation

  Inconsistencies are handled by the cluster reconciliation worker.

  ## Parameters
  - `node` - The node struct to move
  - `params` - Request params containing new cluster name (validated through ChangeNodeClusterForm)

  ## Returns
  - `{:ok, updated_node}` - Node cluster changed successfully
  - `{:error, changeset}` - Validation failed (form, schema, or new cluster not found)
  - `{:error, {:conflict, reason}}` - Already in target cluster (`SameClusterCheck`)
    or target cluster at node limit (`NodeLimitCheck`)
  """
  @spec change_node_cluster(Node.t(), map()) ::
          {:ok, Node.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def change_node_cluster(%Node{} = node, params) do
    with {:ok, new_cluster_name} <- Forms.ChangeNodeClusterForm.changeset(params),
         {:ok, %{node: current_node, new_cluster: new_cluster, updated_node: updated_node}} <-
           move_node_to_active_cluster(node.id, new_cluster_name) do
      cleanup_node_aliases(current_node)
      updated_node = Repo.preload(updated_node, [:cluster, aliases: :cluster], force: true)
      Metadata.Events.publish(:node_updated)
      sync_node_cluster_networks(current_node, new_cluster)

      {:ok, updated_node}
    end
  end

  defp move_node_to_active_cluster(node_id, new_cluster_name) do
    Repo.transaction_with_write_lock(fn ->
      with %Node{} = current_node <- Repo.get(Node, node_id),
           current_node = Repo.preload(current_node, :cluster),
           %Cluster{} = new_cluster <- Persistence.lock_active_cluster(new_cluster_name),
           :ok <- Checks.SameClusterCheck.check(current_node, new_cluster),
           :ok <- Checks.NodeLimitCheck.check(new_cluster),
           {:ok, updated_node} <-
             current_node
             |> Ecto.Changeset.change(
               cluster_id: new_cluster.id,
               recovery_key: nil
             )
             |> Repo.update() do
        %{node: current_node, new_cluster: new_cluster, updated_node: updated_node}
      else
        nil -> Repo.rollback(:not_found)
        {:error, _} = error -> Repo.rollback(error)
      end
    end)
  end

  # Best-effort Netmaker network sync after a cluster change.
  # The reconciliation worker will fix any inconsistencies.
  defp sync_node_cluster_networks(node, new_cluster) do
    old_network_name = Cluster.network_name(node.cluster)
    new_network_name = Cluster.network_name(new_cluster)

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
  3. Delete from DB. Cascade behaviour:
     - `ssh_usernames` → `:delete_all` (and their `ssh_public_keys` cascade transitively)
     - `aliases` → `:delete_all`
     - non-terminal `command_executions` → `dropped`, then `:nilify_all`
  4. Emit event for metadata recomputation

  If Netmaker deletion fails (except :not_found), operation stops and returns error.
  If Netmaker returns :not_found, continues with DB deletion (already gone).

  This ensures "node in DB but host not in Netmaker" always means failed deletion,
  allowing reconciliation to safely delete orphaned DB nodes.

  Returns `{:ok, node}`, `{:error, changeset}` (DB failure), or `{:error, :service_unavailable}` (Netmaker failure).
  """
  @spec delete_node(Node.t()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()} | {:error, :service_unavailable}
  def delete_node(%Node{} = node) do
    node = Repo.preload(node, :cluster)

    # 1. Clean up DNS records (aliases) from Netmaker (best-effort, outside main flow)
    cleanup_node_aliases(node)

    # 2. Delete host from Netmaker FIRST
    case Vpn.delete_host(node.netmaker_host_id) do
      {:ok, _} ->
        Logger.info("Deleted host #{node.netmaker_host_id} from Netmaker")
        sweep_orphan_netmaker_nodes(node)
        delete_node_from_db(node)

      {:error, :not_found} ->
        # Host already gone - continue with DB deletion
        Logger.info("Netmaker host #{node.netmaker_host_id} already deleted")
        sweep_orphan_netmaker_nodes(node)
        delete_node_from_db(node)

      {:error, :service_unavailable} = error ->
        # Netmaker failed - stop operation
        Logger.error("Failed to delete Netmaker host #{node.netmaker_host_id}, aborting node deletion")
        error
    end
  end

  # Defends against a Netmaker bug: `RemoveHost` (logic/hosts.go) iterates the
  # cached `host.Nodes` slice instead of querying the nodes table by host_id.
  # Node rows that drifted out of that cache (e.g. enroll racing with delete)
  # survive the host delete and remain visible in peer pulls as dead allowed-ips.
  #
  # After deleting the host, list the network's nodes and force-delete any whose
  # `hostid` still matches the host we just removed. The per-node delete endpoint
  # routes through `DeleteNode(purge=true)` which keys off node_id directly and
  # skips the broken read path.
  #
  # Best-effort; failures are logged. The periodic reconciler is the backstop.
  defp sweep_orphan_netmaker_nodes(%Node{cluster: %Ecto.Association.NotLoaded{}}), do: :ok

  defp sweep_orphan_netmaker_nodes(%Node{} = node) do
    network_name = Cluster.network_name(node.cluster)

    case Vpn.list_nodes(network_name) do
      {:ok, nm_nodes} ->
        nm_nodes
        |> Enum.filter(fn nm_node -> nm_node["hostid"] == node.netmaker_host_id end)
        |> Enum.each(fn nm_node -> delete_orphan_node(network_name, nm_node, node.netmaker_host_id) end)

      {:error, reason} ->
        Logger.warning("Orphan sweep: could not list Netmaker nodes for #{network_name}: #{inspect(reason)}")
    end
  end

  defp delete_orphan_node(network_name, nm_node, host_id) do
    node_id = nm_node["id"]

    case Vpn.delete_node(network_name, node_id) do
      {:ok, _} ->
        Logger.warning("Orphan sweep: removed Netmaker node #{node_id} (host #{host_id}) from #{network_name}")

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        Logger.error("Orphan sweep: failed to remove Netmaker node #{node_id} from #{network_name}: #{inspect(reason)}")
    end
  end

  defp delete_node_from_db(%Node{} = node) do
    node = Repo.preload(node, :cluster)

    case Repo.transaction(fn ->
           dropped_executions = Commands.drop_node_executions(node.id, node.cluster.name)

           case Repo.delete(node) do
             {:ok, deleted_node} -> {deleted_node, dropped_executions}
             {:error, changeset} -> Repo.rollback(changeset)
           end
         end) do
      {:ok, {deleted_node, dropped_executions}} ->
        Commands.publish_dropped_executions(dropped_executions)
        Metadata.Events.publish(:node_deleted)
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
  Registers a new node or recovers an existing node from agent bootstrap.

  ## Token rotation (security-relevant)

  Both `api_token` and `proxy_password` are generated on every successful
  registration. An existing node can only be recovered with its one-use
  recovery key. Normal re-registration is handled by `reregister_node/2`.

  ## Limits

  `NodeLimitCheck` is enforced for new nodes only.

  ## Parameters
  - `params` - Node registration parameters (validated through RegisterNodeForm)

  ## Returns
  - `{:ok, node}` - Node registered or recovered successfully
  - `{:error, changeset}` - Validation or registration failed
  """
  @spec register_node(map()) ::
          {:ok, Node.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized | {:conflict, String.t()}}
  def register_node(params) do
    with {:ok, registration} <- Registration.register(params) do
      finalize_registration(registration)
    end
  end

  # ===========================================================================
  # Enrollment Key functions
  # ===========================================================================
  @doc """
  Re-registers the node authenticated by the Agent API token.
  """
  @spec reregister_node(Node.t(), map()) ::
          {:ok, Node.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def reregister_node(%Node{} = node, params) do
    with {:ok, registration} <- Registration.reregister(node, params) do
      finalize_registration(registration)
    end
  end

  defp finalize_registration(%{node: node, existing_node: existing_node, is_new_node: is_new_node}) do
    node = Repo.preload(node, [:cluster], force: true)

    if is_new_node do
      Metadata.Events.publish(:node_created)
      Events.publish(%Catalog.NodeRegistered{node: node})
    else
      Events.publish(%Catalog.NodeReregistered{node: node})

      if existing_node.version != node.version do
        Events.publish(%Catalog.NodeVersionChanged{
          node: node,
          previous_version: existing_node.version
        })
      end
    end

    Aliases.repair_node_dns(node)

    {:ok, node}
  end

  @doc "Records an agent health report received through HTTP fallback mode."
  @spec update_node_health_check(Node.t(), map()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()}
  defdelegate update_node_health_check(node, params), to: HealthCheck

  @doc "Performs the scheduled health check for nodes assigned to this Admin."
  @spec check_node_health() :: :ok
  defdelegate check_node_health(), to: HealthCheck

  @doc "Returns a live or recently cached diagnostic report for a node."
  @spec get_node_diagnostics(String.t()) ::
          {:ok, map()} | {:error, :not_found | :service_unavailable}
  defdelegate get_node_diagnostics(node_id), to: Diagnostics

  @doc "Stores the latest diagnostic report for a node."
  @spec upsert_node_diagnostic(String.t(), map()) ::
          {:ok, NodeDiagnostic.t()} | {:error, Ecto.Changeset.t()}
  defdelegate upsert_node_diagnostic(node_id, report), to: Diagnostics

  @doc "Returns a recent cached diagnostic report for a node, if available."
  @spec get_cached_node_diagnostic(String.t()) ::
          NodeDiagnostic.t() | nil
  defdelegate get_cached_node_diagnostic(node_id), to: Diagnostics

  @doc """
  Lists nodes with filtering, sorting, and pagination.

  Supports filtering by:
  - `status__in` - Enum IN: `"healthy"`, `"unhealthy"`, `"unreachable"` — comma-separated list (`status__in=healthy,unhealthy`)
  - `version` - Text search with wildcard support (1.0.0 exact, 1.* ilike)
  - `self_update_enabled` - Boolean
  - `last_seen_at__gte/lte` - Datetime range filter
  - `inserted_at__gte/lte` - Date range filter
  - `updated_at__gte/lte` - Date range filter
  - `cluster_name` - Exact match or wildcard (`prod*`) on cluster name (requires join)
  - `cluster_name__in` - IN match on cluster name — comma-separated list (requires join)
  - `node_id__in` - Exact IN match on node IDs — comma-separated UUIDs
  - `enrollment_key_id__in` - Exact IN match on enrollment-key IDs — comma-separated UUIDs
  - `has_enrollment_key` - Boolean: whether the node has an enrollment-key association

  ## Returns
  - `{:ok, {nodes, meta}}` - List of nodes with Flop.Meta pagination info
  - `{:error, meta}` - Validation errors (when replace_invalid_params: false)
  """

  @spec list_nodes(map()) :: {:ok, {[Node.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_nodes(params \\ %{}) do
    flop_params = RequestParser.parse(params)
    {query, flop_params} = node_filter_query(flop_params)

    case Flop.validate_and_run(query, flop_params,
           for: Node,
           replace_invalid_params: true
         ) do
      {:ok, {nodes, meta}} ->
        {:ok, {nodes, meta}}

      {:error, meta} ->
        {:error, meta}
    end
  end

  @doc """
  Lists every node matching the list-node filters for Prometheus discovery.

  Discovery is a complete HTTP SD snapshot, so it deliberately does not apply
  pagination or sorting. When `status__in` is absent, all statuses — including
  `unreachable` — are returned.
  """
  @spec list_nodes_for_discovery(map()) :: {:ok, [Node.t()]} | {:error, Flop.Meta.t()}
  def list_nodes_for_discovery(params \\ %{}) do
    flop_params =
      params
      |> RequestParser.parse()
      |> Map.drop([:page, :page_size, :order_by, :order_directions])

    {query, flop_params} = node_filter_query(flop_params)

    discovery_opts = [
      for: Node,
      replace_invalid_params: true,
      default_limit: false,
      default_order: false,
      default_pagination_type: false
    ]

    case Flop.validate(flop_params, discovery_opts) do
      {:ok, flop} -> {:ok, Flop.all(query, flop, discovery_opts)}
      {:error, meta} -> {:error, meta}
    end
  end

  defp node_filter_query(flop_params) do
    {cluster_name_filters, other_filters} =
      Enum.split_with(flop_params[:filters] || [], fn filter ->
        filter.field == :cluster_name
      end)

    {node_ids_filters, other_filters} =
      Enum.split_with(other_filters, fn filter -> filter.field == :node_id end)

    {enrollment_key_ids_filters, other_filters} =
      Enum.split_with(other_filters, fn filter -> filter.field == :enrollment_key_id end)

    {has_enrollment_key_filters, other_filters} =
      Enum.split_with(other_filters, fn filter -> filter.field == :has_enrollment_key end)

    {ilike_filters, flop_params} =
      RequestParser.split_ilike_filters(
        Map.put(flop_params, :filters, other_filters),
        [:version]
      )

    query =
      from(n in Node,
        join: c in assoc(n, :cluster),
        preload: [:cluster, aliases: :cluster]
      )
      |> ClusterQueries.active_joined()
      |> ClusterFilters.apply_name(cluster_name_filters)
      |> NodeFilters.apply_node_ids(node_ids_filters)
      |> NodeFilters.apply_enrollment_key_ids(enrollment_key_ids_filters)
      |> NodeFilters.apply_has_enrollment_key(has_enrollment_key_filters)
      |> NodeFilters.apply_ilike(ilike_filters)

    {query, flop_params}
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
        from c in ClusterQueries.active(),
          join: n in assoc(c, :nodes),
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
        if Repo.exists?(ClusterQueries.active_by_name(cluster_name)) do
          {:ok, %{}}
        else
          # ===========================================================================
          # Reconciliation functions
          # ===========================================================================
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

            # ===========================================================================
            # Alias functions
            # ===========================================================================
            case row.alias_name do
              nil -> acc
              name -> Map.put(acc, name, node)
            end
          end)

        {:ok, identifiers_map}
    end
  end

  @doc "Delegates enrollment-key listing to the enrollment-key resource module."
  @spec list_enrollment_keys(map()) :: {:ok, {[EnrollmentKey.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_enrollment_keys(params \\ %{}), do: EnrollmentKeys.list(params)

  @doc "Delegates enrollment-key lookup to the enrollment-key resource module."
  @spec get_enrollment_key(String.t()) :: {:ok, EnrollmentKey.t()} | {:error, :not_found}
  def get_enrollment_key(id), do: EnrollmentKeys.get(id)

  @doc """
  Creates an enrollment key for a cluster.

  Generates a base64 JSON blob stored in the `key` column and returned to the
  operator for placement in the agent's ENROLLMENT_KEY env var:

      base64({"admin_urls": [...], "cluster_name": "<cluster>", "nonce": "<random_32_bytes_base64>"})

  The agent decodes the blob to extract `admin_urls` (for routing) and sends
  the full blob to the verify endpoint. Admin looks up by the blob directly —
  no inner nonce comparison needed.

  The nonce exists solely to make each key unique and unguessable.
  """
  @spec create_enrollment_key(Cluster.t(), map()) ::
          {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  def create_enrollment_key(%Cluster{} = cluster, params \\ %{}), do: EnrollmentKeys.create(cluster, params)

  @doc """
  Updates an enrollment key's `uses_remaining` and/or `expires_at`.

  Only fields explicitly provided are updated. Pass null to unset `expires_at`.
  """
  @spec update_enrollment_key(EnrollmentKey.t(), map()) ::
          {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  def update_enrollment_key(%EnrollmentKey{} = key, params), do: EnrollmentKeys.update(key, params)

  @doc """
  Deletes an enrollment key.
  """
  @spec delete_enrollment_key(EnrollmentKey.t()) ::
          {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  def delete_enrollment_key(%EnrollmentKey{} = key), do: EnrollmentKeys.delete(key)

  @doc """
  Verifies an enrollment key blob presented by an agent before it joins the VPN.

  The agent sends the full key blob (the base64 JSON string). Admin looks it up
  directly in the DB and confirms the embedded cluster name matches the key's
  associated cluster.

  Performs the following checks in order:
  1. Key blob exists in DB
  2. Key is not expired
  3. Key is not spent (uses_remaining == 0; null means unlimited)
  4. Cluster has capacity (NodeLimitCheck)

  On success, atomically decrements `uses_remaining` (unless unlimited) and sets
  `last_used_at`, then fetches the Netmaker default enrollment key for the cluster.

  The decrement uses a conditional UPDATE to prevent race conditions when two agents
  simultaneously attempt to consume the last use of a key.

  ## Returns

  - `{:ok, %{error: String.t(), netmaker_key: String.t(), enrollment_key_id: String.t() | nil}}` —
    on every input that survives form validation. A non-nil
    `enrollment_key_id` indicates successful verification; `nil` indicates
    that verification failed.
  - `{:error, changeset}` — input failed `VerifyEnrollmentKeyForm` validation
    (e.g. missing `key`).
  """
  @spec verify_enrollment_key(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def verify_enrollment_key(params), do: EnrollmentKeys.verify(params)

  @doc "Reconciles all active clusters with Netmaker."
  defdelegate reconcile_clusters(), to: Reconciliation

  @doc "Reconciles one active cluster with Netmaker."
  defdelegate reconcile_cluster(cluster_name), to: Reconciliation

  @doc "Completes deletion of a retired cluster."
  defdelegate complete_cluster_deletion(cluster_name, cluster_id), to: Reconciliation

  @doc "Enqueues cluster reconciliation and retired-cluster deletion work."
  defdelegate enqueue_cluster_reconciliation(), to: Reconciliation

  @doc "Cleans up aliases for a node and their Netmaker DNS entries."
  defdelegate cleanup_node_aliases(node), to: Aliases

  @doc "Cleans up aliases belonging to orphaned nodes."
  defdelegate cleanup_orphaned_aliases(nodes), to: Aliases

  @doc "Lists aliases with filtering and pagination."
  defdelegate list_aliases(params \\ %{}), to: Aliases, as: :list

  @doc "Gets an alias by ID."
  defdelegate get_alias(id), to: Aliases, as: :get

  @doc "Creates an alias and its Netmaker DNS entry."
  defdelegate create_alias(node, params), to: Aliases, as: :create

  @doc "Deletes an alias and its Netmaker DNS entry."
  defdelegate delete_alias(alias_record), to: Aliases, as: :delete

  @doc "Returns an alias changeset."
  defdelegate change_alias(alias_record, attrs \\ %{}), to: Aliases, as: :change

  @doc "Reconciles alias DNS entries for active clusters."
  defdelegate cleanup_ghost_aliases(clusters, acc), to: Aliases
end
