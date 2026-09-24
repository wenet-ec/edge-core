# edge_admin/lib/edge_admin/nodes/nodes.ex
defmodule EdgeAdmin.Nodes do
  @moduledoc """
  The Nodes context handles edge agent node management.

  Nodes represent edge devices (agents) enrolled in the system. Each node belongs
  to a cluster and can execute commands via SSH or proxy connections.

  The database is the canonical record for cluster and node state. VPN resources
  are reconciled separately, so operations that touch both systems can have a
  partial-failure window. Reconciliation restores missing or stale VPN
  resources from active database records and removes unowned resources.

  Cluster retirement is recorded before external cleanup. Alias records are
  persisted with their DNS lifecycle coordinated against the VPN provider.
  Address allocation considers both database ranges and ranges reported by the
  VPN provider.

  """

  alias EdgeAdmin.Nodes.Forms.PushNodeDiagnosticForm
  alias EdgeAdmin.Nodes.Resources.AliasResources
  alias EdgeAdmin.Nodes.Resources.ClusterResources
  alias EdgeAdmin.Nodes.Resources.DiagnosticResources
  alias EdgeAdmin.Nodes.Resources.EnrollmentKeyResources
  alias EdgeAdmin.Nodes.Resources.NodeResources
  alias EdgeAdmin.Nodes.Resources.ProxyResources
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Schemas.NodeDiagnostic
  alias EdgeAdmin.Nodes.Workflows.ClusterDeletion
  alias EdgeAdmin.Nodes.Workflows.ClusterReconciliation
  alias EdgeAdmin.Nodes.Workflows.HealthCheck

  @doc """
  Lists all clusters with node counts, filtering, and pagination.

  Retired clusters are not returned.

  Supports the cluster filters, sorting, and pagination defined by the Nodes
  query surface.

  Returns `{:ok, {clusters, meta}}` or `{:error, meta}`.
  """
  @spec list_clusters(map()) :: {:ok, {[Cluster.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_clusters(params \\ %{}), to: ClusterResources, as: :list

  @doc """
  Lists cluster-node mappings.

  Options control whether names are prefixed and which node statuses are
  included. Returns one mapping per cluster with its node identifiers.
  """
  @spec list_cluster_node_mappings(keyword()) :: [map()]
  defdelegate list_cluster_node_mappings(opts \\ []), to: ClusterResources, as: :list_node_mappings

  @doc "Returns the configured default cluster name, if one is set."
  @spec default_cluster_name() :: String.t() | nil
  defdelegate default_cluster_name(), to: ClusterResources

  @doc """
  Gets a single cluster by name.

  Returns the cluster with nodes preloaded, or `{:error, :not_found}`.
  """
  @spec get_cluster(String.t()) :: {:ok, Cluster.t()} | {:error, :not_found}
  defdelegate get_cluster(name), to: ClusterResources, as: :get

  @doc """
  Creates a cluster and its Edge VPN network.

  Validates and allocates both address families, persists the cluster, provisions
  its VPN network, and emits the metadata update event. VPN availability and
  creation failures are returned without leaving an active database row.

  A later missing network does not make the active DB cluster disposable: the active
  row is the desired configuration, so reconciliation recreates the network from it.

  Returns `{:ok, cluster}`, `{:error, changeset}` (validation), `{:error, {:conflict, reason}}` (CIDR overlap or node-limit/resource-state conflict), or `{:error, :service_unavailable}` (health check or Edge VPN failure).
  """
  @spec create_cluster(map()) ::
          {:ok, Cluster.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:conflict, String.t()}}
          | {:error, :service_unavailable}
  defdelegate create_cluster(attrs \\ %{}), to: ClusterResources, as: :create_with_vpn_network

  @doc """
  Updates a cluster.

  `node_limit` is an Edge Admin policy and is intentionally not sent to Edge VPN.
  Edge VPN's network membership includes both Admin and Agent hosts, so its own
  network-level limit would not represent this cluster's edge-node limit.
  The active cluster row is re-read and locked before the limit is checked or updated.

  Returns `{:error, :not_found}` when the cluster was retired or no longer exists.
  """
  @spec update_cluster(Cluster.t(), map()) ::
          {:ok, Cluster.t()}
          | {:error, :not_found}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:conflict, String.t()}}
  defdelegate update_cluster(cluster, params), to: ClusterResources, as: :update_active

  @doc """
  Retires an empty cluster from the public API and enqueues Edge VPN cleanup.

  The retirement transaction locks the active cluster, rechecks that it is empty, writes
  `deleted_at`, and inserts the deletion job atomically. New registration and
  cluster-move paths use the same short transaction boundary, so they cannot enter a
  cluster after retirement wins. Edge VPN deletion happens asynchronously after commit.

  Returns `{:ok, cluster}`, `{:error, :not_found}`, or
  `{:error, {:conflict, reason}}` when the cluster has nodes.
  """
  @spec delete_cluster(Cluster.t()) ::
          {:ok, Cluster.t()}
          | {:error, :not_found}
          | {:error, {:conflict, String.t()}}
          | {:error, :service_unavailable}
  defdelegate delete_cluster(cluster), to: ClusterResources, as: :retire

  @doc """
  Gets a single node by ID.

  Returns the node with cluster and aliases preloaded, or `{:error, :not_found}`.
  """
  @spec get_node(String.t()) :: {:ok, Node.t()} | {:error, :not_found}
  defdelegate get_node(id), to: NodeResources, as: :get

  @doc """
  Creates or replaces a node's one-use recovery key.

  The returned value is the complete base64 JSON blob the operator supplies to
  a fresh Agent as `RECOVERY_KEY` alongside its normal enrollment key.
  """
  @spec create_node_recovery_key(Node.t()) :: {:ok, String.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_node_recovery_key(node), to: NodeResources, as: :create_recovery_key

  @doc """
  Deletes a node's active recovery key.
  """
  @spec delete_node_recovery_key(Node.t()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()}
  defdelegate delete_node_recovery_key(node), to: NodeResources, as: :delete_recovery_key

  @doc """
  Changes a node's cluster.

  DB-first approach: Updates database immediately, then best-effort syncs with Edge VPN.
  A background reconciliation worker handles any inconsistencies.

  Flow:
  1. Serialize the target-cluster admission and update the database (source of truth)
  2. Clear the recovery key and delete all aliases (they're cluster-specific)
  3. Best-effort sync: Add host to new network
  4. Best-effort sync: Remove host from old network
  5. Emit event for metadata recomputation

  Inconsistencies are handled by the cluster reconciliation worker.

  Returns a conflict when the node is already in the target cluster or the
  target cluster is at its node limit.
  """
  @spec change_node_cluster(Node.t(), map()) ::
          {:ok, Node.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  defdelegate change_node_cluster(node, params), to: NodeResources, as: :change_cluster

  @doc """
  Deletes a node and its VPN host.

  Flow (Edge VPN-first):
  1. Clean up DNS records (aliases) from Edge VPN (best-effort)
  2. Delete host from Edge VPN FIRST
  3. Delete from DB. Cascade behaviour:
     - `ssh_usernames` → `:delete_all` (and their `ssh_public_keys` cascade transitively)
     - `aliases` → `:delete_all`
     - non-terminal `command_executions` → `dropped`, then `:nilify_all`
  4. Emit event for metadata recomputation

  If Edge VPN deletion fails (except :not_found), operation stops and returns error.
  If Edge VPN returns :not_found, continues with DB deletion (already gone).

  This ensures "node in DB but host not in Edge VPN" always means failed deletion,
  allowing reconciliation to safely delete orphaned DB nodes.

  Returns `{:ok, node}`, `{:error, changeset}` (DB failure), or `{:error, :service_unavailable}` (Edge VPN failure).
  """
  @spec delete_node(Node.t()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()} | {:error, :service_unavailable}
  defdelegate delete_node(node), to: NodeResources

  @doc """
  Registers a new node or recovers an existing node from agent bootstrap.

  ## Token rotation (security-relevant)

  Both `api_token` and `proxy_password` are generated on every successful
  registration. An existing node can only be recovered with its one-use
  recovery key. Normal re-registration is handled by `reregister_node/2`.

  ## Limits

  `NodeLimitCheck` is enforced for new nodes only.
  """
  @spec register_node(map()) ::
          {:ok, Node.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized | {:conflict, String.t()}}
  defdelegate register_node(params), to: NodeResources, as: :register

  @doc """
  Re-registers the node authenticated by the Agent API token.
  """
  @spec reregister_node(Node.t(), map()) ::
          {:ok, Node.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  defdelegate reregister_node(node, params), to: NodeResources, as: :reregister

  @doc "Records an agent health report received through HTTP fallback mode."
  @spec update_node_health_check(Node.t(), map()) :: {:ok, Node.t()} | {:error, Ecto.Changeset.t()}
  defdelegate update_node_health_check(node, params), to: HealthCheck

  @doc "Performs the scheduled health check for nodes assigned to this Admin."
  @spec check_node_health() :: :ok
  defdelegate check_node_health(), to: HealthCheck

  @doc "Returns a live or recently cached diagnostic report for a node."
  @spec get_node_diagnostics(String.t()) ::
          {:ok, map()} | {:error, :not_found | :service_unavailable}
  defdelegate get_node_diagnostics(node_id), to: DiagnosticResources

  @doc "Stores the latest diagnostic report for a node."
  @spec upsert_node_diagnostic(String.t(), map()) ::
          {:ok, NodeDiagnostic.t()} | {:error, Ecto.Changeset.t()}
  defdelegate upsert_node_diagnostic(node_id, report), to: DiagnosticResources, as: :upsert

  @doc "Validates and stores an agent-pushed diagnostic report."
  @spec push_node_diagnostic(String.t(), map()) :: {:ok, NodeDiagnostic.t()} | {:error, Ecto.Changeset.t()}
  def push_node_diagnostic(node_id, params) do
    with {:ok, attrs} <- PushNodeDiagnosticForm.changeset(params) do
      upsert_node_diagnostic(node_id, attrs["diagnostic"])
    end
  end

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

  Returns `{:ok, {nodes, meta}}` or `{:error, meta}`.
  """

  @spec list_nodes(map()) :: {:ok, {[Node.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_nodes(params \\ %{}), to: NodeResources, as: :list

  @doc """
  Lists every node matching the list-node filters for Prometheus discovery.

  Discovery is a complete HTTP SD snapshot, so it deliberately does not apply
  pagination or sorting. When `status__in` is absent, all statuses — including
  `unreachable` — are returned.
  """
  @spec list_nodes_for_discovery(map()) :: {:ok, [Node.t()]} | {:error, Flop.Meta.t()}
  defdelegate list_nodes_for_discovery(params \\ %{}), to: NodeResources, as: :list_for_discovery

  @doc """
  Lists all valid node identifiers (IDs and aliases) for a cluster.

  Returns a map of identifier to node, keyed by each node ID and alias, or
  `{:error, :not_found}` when the cluster does not exist.
  """
  @callback list_proxy_chain_identifiers(String.t()) :: {:ok, map()} | {:error, :not_found}
  @spec list_proxy_chain_identifiers(String.t()) :: {:ok, map()} | {:error, :not_found}
  defdelegate list_proxy_chain_identifiers(cluster_name), to: ProxyResources, as: :get_chain_identifiers

  @spec list_enrollment_keys(map()) :: {:ok, {[EnrollmentKey.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list_enrollment_keys(params \\ %{}), do: EnrollmentKeyResources.list(params)

  @spec get_enrollment_key(String.t()) :: {:ok, EnrollmentKey.t()} | {:error, :not_found}
  def get_enrollment_key(id), do: EnrollmentKeyResources.get(id)

  @doc """
  Creates an enrollment key for a cluster.

  Generates a unique enrollment blob, stores it with the cluster association,
  and returns it for agent enrollment. Verification uses the complete blob and
  atomically consumes limited-use keys.
  """
  @spec create_enrollment_key(Cluster.t(), map()) ::
          {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_enrollment_key(cluster, params \\ %{}), to: EnrollmentKeyResources, as: :create_for_cluster

  @doc """
  Updates an enrollment key's `uses_remaining` and/or `expires_at`.

  Only fields explicitly provided are updated. Pass null to unset `expires_at`.
  """
  @spec update_enrollment_key(EnrollmentKey.t(), map()) ::
          {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  defdelegate update_enrollment_key(key, params), to: EnrollmentKeyResources

  @doc """
  Deletes an enrollment key.
  """
  @spec delete_enrollment_key(EnrollmentKey.t()) ::
          {:ok, EnrollmentKey.t()} | {:error, Ecto.Changeset.t()}
  def delete_enrollment_key(%EnrollmentKey{} = key), do: EnrollmentKeyResources.delete(key)

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
  `last_used_at`, then fetches the Edge VPN default enrollment key for the cluster.

  The decrement uses a conditional UPDATE to prevent race conditions when two agents
  simultaneously attempt to consume the last use of a key.

  Returns `{:ok, result}` for every input that survives form validation. A
  non-nil `enrollment_key_id` indicates successful verification; `nil`
  indicates verification failed.
  """
  @spec verify_enrollment_key(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def verify_enrollment_key(params), do: EnrollmentKeyResources.verify(params)

  @doc "Reconciles one active cluster with Edge VPN."
  defdelegate reconcile_cluster(cluster_name), to: ClusterReconciliation

  @doc "Completes deletion of a retired cluster."
  defdelegate complete_cluster_deletion(cluster_name, cluster_id), to: ClusterDeletion

  @doc "Enqueues cluster reconciliation and retired-cluster deletion work."
  defdelegate enqueue_cluster_reconciliation(), to: ClusterReconciliation

  @doc "Lists aliases with filtering and pagination."
  defdelegate list_aliases(params \\ %{}), to: AliasResources, as: :list

  defdelegate get_alias(id), to: AliasResources, as: :get

  @doc "Creates an alias and its Edge VPN DNS entry."
  defdelegate create_alias(node, params), to: AliasResources, as: :create_with_dns

  @doc "Deletes an alias and its Edge VPN DNS entry."
  defdelegate delete_alias(alias_record), to: AliasResources, as: :delete_with_dns
end
