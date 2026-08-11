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

  alias EdgeAdmin.Nodes.Resources.Aliases
  alias EdgeAdmin.Nodes.Resources.Clusters
  alias EdgeAdmin.Nodes.Resources.Diagnostics
  alias EdgeAdmin.Nodes.Resources.EnrollmentKeys
  alias EdgeAdmin.Nodes.Resources.Nodes, as: NodeResource
  alias EdgeAdmin.Nodes.Resources.Proxy, as: ProxyResource
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Schemas.NodeDiagnostic
  alias EdgeAdmin.Nodes.Workflows.HealthCheck
  alias EdgeAdmin.Nodes.Workflows.Reconciliation

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
  defdelegate list_clusters(params \\ %{}), to: Clusters, as: :list

  @doc "Lists active and retired clusters for maintenance reconciliation."
  @spec list_clusters_for_reconciliation(map()) ::
          {:ok, {[Cluster.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_clusters_for_reconciliation(params), to: Clusters, as: :list_for_reconciliation

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
  defdelegate list_cluster_node_mappings(opts \\ []), to: Clusters, as: :list_node_mappings

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
  defdelegate get_cluster(name), to: Clusters, as: :get

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
  defdelegate create_cluster(attrs \\ %{}), to: Clusters, as: :create

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
  defdelegate update_cluster(cluster, params), to: Clusters, as: :update

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
  defdelegate delete_cluster(cluster), to: Clusters, as: :delete

  @doc """
  Returns a changeset for tracking cluster changes (for forms).

  ## Examples

      iex> change_cluster(cluster)
      %Ecto.Changeset{data: %Cluster{}}
  """
  @spec change_cluster(Cluster.t(), map()) :: Ecto.Changeset.t()
  defdelegate change_cluster(cluster, attrs \\ %{}), to: Clusters, as: :change

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
  defdelegate get_node(id), to: NodeResource, as: :get

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
  defdelegate create_node(attrs \\ %{}), to: NodeResource, as: :create

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
  defdelegate update_node(node, attrs), to: NodeResource, as: :update

  @doc """
  Creates or replaces a node's one-use recovery key.

  The returned value is the complete base64 JSON blob the operator supplies to
  a fresh Agent as `RECOVERY_KEY` alongside its normal enrollment key.
  """
  @spec create_node_recovery_key(Node.t()) :: {:ok, String.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_node_recovery_key(node), to: NodeResource, as: :create_recovery_key

  @doc """
  Deletes a node's active recovery key.
  """
  @spec delete_node_recovery_key(Node.t()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()}
  defdelegate delete_node_recovery_key(node), to: NodeResource, as: :delete_recovery_key

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
  defdelegate change_node_cluster(node, params), to: NodeResource, as: :change_cluster

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
  defdelegate delete_node(node), to: NodeResource

  @doc """
  Returns a changeset for tracking node changes (for forms).

  ## Examples

      iex> change_node(node)
      %Ecto.Changeset{data: %Node{}}
  """
  @spec change_node(Node.t(), map()) :: Ecto.Changeset.t()
  defdelegate change_node(node, attrs \\ %{}), to: NodeResource, as: :change

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
  defdelegate register_node(params), to: NodeResource, as: :register

  # ===========================================================================
  # Enrollment Key functions
  # ===========================================================================
  @doc """
  Re-registers the node authenticated by the Agent API token.
  """
  @spec reregister_node(Node.t(), map()) ::
          {:ok, Node.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  defdelegate reregister_node(node, params), to: NodeResource, as: :reregister

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
  defdelegate list_nodes(params \\ %{}), to: NodeResource, as: :list

  @doc """
  Lists every node matching the list-node filters for Prometheus discovery.

  Discovery is a complete HTTP SD snapshot, so it deliberately does not apply
  pagination or sorting. When `status__in` is absent, all statuses — including
  `unreachable` — are returned.
  """
  @spec list_nodes_for_discovery(map()) :: {:ok, [Node.t()]} | {:error, Flop.Meta.t()}
  defdelegate list_nodes_for_discovery(params \\ %{}), to: NodeResource, as: :list_for_discovery

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
  defdelegate get_nodes_by_ids(node_ids), to: NodeResource, as: :get_by_ids

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
  defdelegate list_proxy_chain_identifiers(cluster_name), to: ProxyResource, as: :list_chain_identifiers

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
