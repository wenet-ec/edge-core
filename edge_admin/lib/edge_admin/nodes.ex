# edge_admin/lib/edge_admin/nodes.ex
defmodule EdgeAdmin.Nodes do
  @moduledoc """
  The Nodes context.
  """

  import Ecto.Query, warn: false

  alias EdgeAdmin.FilteringPagination
  alias EdgeAdmin.Nodes.Alias
  alias EdgeAdmin.Nodes.Cluster
  alias EdgeAdmin.Nodes.EphemeralEnrollmentKey
  alias EdgeAdmin.Nodes.Metrics
  alias EdgeAdmin.Nodes.Node
  alias EdgeAdmin.Nodes.SshPublicKey
  alias EdgeAdmin.Nodes.SshUsername
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Vpn

  require Logger

  # ===========================================================================
  # Cluster functions
  # ===========================================================================

  @doc """
  Lists all clusters with node counts, filtering, and pagination.

  Supports filtering by:
  - `ipv4_range` - Text search (e.g., "100.64.1")
  - `node_count` - Range queries (e.g., "gte:5", "lt:10", "0")

  Supports sorting by:
  - `inserted_at`, `updated_at`, `ipv4_range`, `node_count`
  """
  def list_clusters_with_filtering_pagination(params \\ %{}) do
    # Extract node_count filter to handle separately
    {node_count_filter, other_params} = Map.pop(params, "node_count")

    base_query =
      from(c in Cluster,
        left_join: n in assoc(c, :nodes),
        group_by: c.id,
        select_merge: %{node_count: count(n.id)}
      )

    # Apply node_count HAVING filter if present
    query_with_having =
      if node_count_filter do
        apply_node_count_filter(base_query, node_count_filter)
      else
        base_query
      end

    # Use FilteringPagination for the rest
    result =
      FilteringPagination.paginate(
        query_with_having,
        other_params,
        filterable_fields: [:ipv4_range],
        sortable_fields: [:inserted_at, :updated_at, :ipv4_range, :node_count],
        default_sort: "inserted_at:desc",
        repo: Repo
      )

    # Re-add node_count to filters if it was present
    if node_count_filter do
      %{result | filters: Map.put(result.filters, "node_count", node_count_filter)}
    else
      result
    end
  end

  defp apply_node_count_filter(query, filter_value) do
    cond do
      # Range queries: gte:5, lt:10, etc.
      String.contains?(filter_value, ":") ->
        case String.split(filter_value, ":", parts: 2) do
          ["gte", val] ->
            {num, _} = Integer.parse(val)
            from([c, n] in query, having: count(n.id) >= ^num)

          ["gt", val] ->
            {num, _} = Integer.parse(val)
            from([c, n] in query, having: count(n.id) > ^num)

          ["lte", val] ->
            {num, _} = Integer.parse(val)
            from([c, n] in query, having: count(n.id) <= ^num)

          ["lt", val] ->
            {num, _} = Integer.parse(val)
            from([c, n] in query, having: count(n.id) < ^num)

          _ ->
            query
        end

      # Exact match: "5" means exactly 5 nodes
      true ->
        case Integer.parse(filter_value) do
          {num, ""} -> from([c, n] in query, having: count(n.id) == ^num)
          _ -> query
        end
    end
  end

  @doc """
  Lists all clusters with node counts (no pagination).
  """
  def list_clusters do
    from(c in Cluster,
      left_join: n in assoc(c, :nodes),
      group_by: c.id,
      select_merge: %{node_count: count(n.id)},
      order_by: [desc: c.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single cluster by name.
  Raises `Ecto.NoResultsError` if the Cluster does not exist.
  """
  def get_cluster!(name) do
    from(c in Cluster,
      left_join: n in assoc(c, :nodes),
      where: c.name == ^name,
      group_by: c.id,
      select_merge: %{node_count: count(n.id)}
    )
    |> Repo.one!()
  end

  @doc """
  Gets a single cluster by name.
  Returns `nil` if the Cluster does not exist.
  """
  def get_cluster(name) do
    from(c in Cluster,
      left_join: n in assoc(c, :nodes),
      where: c.name == ^name,
      group_by: c.id,
      select_merge: %{node_count: count(n.id)}
    )
    |> Repo.one()
  end

  @doc """
  Creates a cluster with automatic name/IP range generation and Netmaker network creation.
  """
  def create_cluster(attrs \\ %{}) do
    Repo.transaction(fn ->
      # 1. Auto-generate IP range if not provided
      existing_ranges = Repo.all(from(c in Cluster, select: c.ipv4_range))
      ipv4_range = attrs["ipv4_range"] || attrs[:ipv4_range] || Vpn.generate_next_subnet(existing_ranges)

      # 2. Merge IP range into attrs (maintain existing key type)
      cluster_attrs = Map.put(attrs, "ipv4_range", ipv4_range)

      # 3. Create cluster in DB (changeset handles name auto-generation)
      cluster =
        %Cluster{}
        |> Cluster.changeset(cluster_attrs)
        |> Repo.insert!()

      # 4. Create Netmaker network
      network_name = Vpn.build_network_name(cluster.name, prefix: :node)

      case Vpn.create_network(network_name, %{addressrange: cluster.ipv4_range}) do
        {:ok, _} ->
          # 5. Broadcast cluster creation event to all admins in this admin cluster
          Phoenix.PubSub.broadcast(
            EdgeAdmin.PubSub,
            "#{Vpn.admin_cluster_name()}:metadata",
            {:cluster_created, cluster.id}
          )

          cluster

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Updates a cluster.
  """
  def update_cluster(%Cluster{} = cluster, attrs) do
    cluster
    |> Cluster.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a cluster and its Netmaker network.
  Fails if cluster has nodes.
  """
  def delete_cluster(%Cluster{} = cluster) do
    Repo.transaction(fn ->
      # 1. Verify cluster is empty (DB constraint also enforces this)
      node_count = Repo.aggregate(from(n in Node, where: n.cluster_id == ^cluster.id), :count)

      if node_count > 0 do
        Repo.rollback(:cluster_not_empty)
      end

      # 2. Delete Netmaker network
      network_name = Vpn.build_network_name(cluster.name, prefix: :node)

      case Vpn.delete_network(network_name) do
        {:ok, _} ->
          # 3. Delete from DB
          deleted_cluster = Repo.delete!(cluster)

          # 4. Broadcast cluster deletion event to all admins in this admin cluster
          Phoenix.PubSub.broadcast(
            EdgeAdmin.PubSub,
            "#{Vpn.admin_cluster_name()}:metadata",
            {:cluster_deleted, cluster.id}
          )

          deleted_cluster

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking cluster changes.
  """
  def change_cluster(%Cluster{} = cluster, attrs \\ %{}) do
    Cluster.changeset(cluster, attrs)
  end


  # ===========================================================================
  # Node functions
  # ===========================================================================

  @doc """
  Returns the HTTP URL for a node.
  Format: http://node-{id}.cluster-{cluster_name}.{domain}:{port}

  Requires cluster association to be preloaded.
  """
  def node_http_url(%Node{http_port: port} = node) do
    "http://#{Node.dns_hostname(node)}:#{port}"
  end

  def get_node!(id) do
    Node
    |> Repo.get!(id)
    |> Repo.preload([:cluster, aliases: :cluster])
  end

  def create_node(attrs \\ %{}) do
    %Node{}
    |> Node.changeset(attrs)
    |> Repo.insert()
  end

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
  """
  def change_node_cluster(%Node{} = node, new_cluster_name) do
    new_cluster = get_cluster!(new_cluster_name)
    old_cluster_id = node.cluster_id

    # 1. Delete all aliases (they're cluster-specific and DNS entries are in old network)
    cleanup_node_aliases(node)

    # 2. Update database first (source of truth)
    updated_node =
      node
      |> Ecto.Changeset.change(cluster_id: new_cluster.id)
      |> Repo.update!()
      |> Repo.preload(:cluster, force: true)

    # 3. Emit PubSub event for metadata recomputation
    Phoenix.PubSub.broadcast(
      EdgeAdmin.PubSub,
      "#{Vpn.admin_cluster_name()}:metadata",
      {:node_updated, node.id, old_cluster_id, new_cluster.id}
    )

    # 4. Best-effort Netmaker sync (don't fail if this doesn't work)
    # The reconciliation worker will fix any inconsistencies
    old_network_name = Vpn.build_network_name(node.cluster.name, prefix: :node)
    new_network_name = Vpn.build_network_name(new_cluster.name, prefix: :node)

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
  end

  @doc """
  Deletes a node and its Netmaker node in a transaction.

  Transaction flow:
  1. Delete node from Netmaker network
  2. Delete from DB (cascades to ssh_usernames, ssh_public_keys, command_executions)
  3. Emit event for metadata recomputation
  """
  def delete_node(%Node{} = node) do
    Repo.transaction(fn ->
      # 1. Remove from Netmaker first (critical - must succeed)
      network_name = Vpn.build_network_name(node.cluster.name, prefix: :node)

      # Remove host from network (Netmaker handles node deletion automatically)
      case Vpn.remove_host_from_network(node.netmaker_host_id, network_name) do
        {:ok, _} ->
          Logger.info("Removed host #{node.netmaker_host_id} from network #{network_name}")

          # 2. Delete from DB (cascades to ssh_usernames, ssh_public_keys, command_executions)
          Repo.delete!(node)

          # 3. Emit PubSub event for metadata recomputation
          Phoenix.PubSub.broadcast(
            EdgeAdmin.PubSub,
            "#{Vpn.admin_cluster_name()}:metadata",
            {:node_deleted, node.id, node.cluster_id}
          )

          node

        {:error, reason} ->
          Logger.error("Failed to remove host from network: #{inspect(reason)}")
          Repo.rollback(reason)
      end
    end)
  end

  def change_node(%Node{} = node, attrs \\ %{}) do
    Node.changeset(node, attrs)
  end

  def get_node(id) do
    {:ok, get_node!(id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  @doc """
  Registers or updates a node from agent.

  Verifies cluster and Netmaker node existence, generates new tokens on every registration,
  and creates or updates the node record.
  """
  def register_agent_node(%{"node" => attrs}) do
    %{
      "node_id" => node_id,
      "network_name" => network_name
    } = attrs

    # 1. Parse cluster name from network name (e.g., "cluster-default" -> "default")
    cluster_name = String.replace_prefix(network_name, "cluster-", "")

    # 2. Verify cluster exists
    cluster = Repo.get_by!(Cluster, name: cluster_name)

    # 3. Verify node exists in Netmaker and get host ID
    node_hostname = Vpn.build_dns_name(node_id, prefix: :node)

    case Vpn.get_host_id(node_hostname, network_name: network_name) do
      {:ok, netmaker_host_id} ->
        # 4. Generate new tokens on every registration
        existing_node = Repo.get(Node, node_id)
        is_new_node = is_nil(existing_node)

        api_token = generate_token()
        proxy_password = generate_token()

        now = DateTime.utc_now() |> DateTime.truncate(:second)

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
          metrics_port: attrs["metrics_port"],
          http_proxy_port: attrs["http_proxy_port"],
          socks5_proxy_port: attrs["socks5_proxy_port"],
          api_token: api_token,
          proxy_password: proxy_password,
          version: attrs["version"],
          self_update_enabled: attrs["self_update_enabled"]
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
              Phoenix.PubSub.broadcast(
                EdgeAdmin.PubSub,
                "#{Vpn.admin_cluster_name()}:metadata",
                {:node_created, node_id, cluster.id}
              )
            end

            {:ok, node, api_token, proxy_password}

          {:error, changeset} ->
            {:error, changeset}
        end

      {:error, _reason} ->
        {:error, :node_not_found_in_netmaker}
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
  end

  @doc """
  Performs health check on all nodes assigned to this admin.

  Called by Quantum scheduler periodically. Reads from Metadata ETS to determine
  which nodes this admin governs, then performs parallel health checks.

  Health check logic:
  - 200 response => status: "healthy", update last_seen_at
  - 503 response => status: "unhealthy", update last_seen_at (we reached it)
  - Network error/timeout => status: "unreachable", don't update last_seen_at

  Logs warnings for unreachable and unhealthy nodes.
  """
  def check_node_health do
    config = Application.get_env(:edge_admin, :node_health_check, [])
    concurrency = Keyword.get(config, :concurrency, 100)
    timeout = Keyword.get(config, :timeout_ms, 10_000)

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
      nodes =
        from(n in Node, where: n.id in ^node_ids, preload: [:cluster])
        |> Repo.all()

      Logger.debug("Starting health check for #{length(nodes)} nodes (concurrency: #{concurrency}, timeout: #{timeout}ms)")
      start_time = System.monotonic_time(:millisecond)

      # Ping all nodes in parallel
      results =
        Task.async_stream(
          nodes,
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

      :ok
    end
  end

  defp ping_node(node, timeout) do
    url = "#{node_http_url(node)}/health"
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    try do
      case Req.get(url, receive_timeout: timeout, retry: false) do
        {:ok, %{status: 200}} ->
          update_node(node, %{status: "healthy", last_seen_at: now})
          :healthy

        {:ok, %{status: 503}} ->
          Logger.warning("Node #{node.id} is unhealthy (503 response)")
          update_node(node, %{status: "unhealthy", last_seen_at: now})
          :unhealthy

        _ ->
          Logger.warning("Node #{node.id} is unreachable")
          update_node(node, %{status: "unreachable"})
          :unreachable
      end
    catch
      _, _ ->
        Logger.warning("Node #{node.id} is unreachable")
        update_node(node, %{status: "unreachable"})
        :unreachable
    end
  end

  @doc """
  Lists all nodes belonging to a specific cluster.
  Used by Metadata for recomputation.
  """
  def list_nodes_by_cluster(cluster_id) do
    from(n in Node,
      where: n.cluster_id == ^cluster_id,
      order_by: [asc: n.inserted_at]
    )
    |> Repo.all()
  end

  def list_nodes_with_filtering_pagination(params \\ %{}) do
    # Handle cluster_name filter specially (join-based)
    {cluster_name_filter, other_params} = Map.pop(params, "cluster_name")

    base_query =
      from(n in Node,
        join: c in assoc(n, :cluster),
        preload: [:cluster, aliases: :cluster]
      )

    # Apply cluster_name filter if present
    query_with_cluster_filter =
      if cluster_name_filter do
        from([n, c] in base_query, where: c.name == ^cluster_name_filter)
      else
        base_query
      end

    # Use FilteringPagination for the rest
    result =
      FilteringPagination.paginate(
        query_with_cluster_filter,
        other_params,
        filterable_fields: [:status, :id_type, :version, :self_update_enabled],
        sortable_fields: [:inserted_at, :updated_at, :status, :last_seen_at],
        default_sort: "inserted_at:desc",
        repo: Repo
      )

    # Re-add cluster_name to filters if it was present
    if cluster_name_filter do
      %{result | filters: Map.put(result.filters, "cluster_name", cluster_name_filter)}
    else
      result
    end
  end

  def get_nodes_by_ids(node_ids) do
    Enum.map(node_ids, fn node_id ->
      try do
        node = get_node!(node_id)
        {:ok, node}
      rescue
        Ecto.NoResultsError ->
          {:error, "Node #{node_id} not found"}
      end
    end)
  end

  def get_ssh_username!(id), do: Repo.get!(SshUsername, id)

  def get_ssh_username_with_keys!(id) do
    Repo.get!(SshUsername, id) |> Repo.preload(:ssh_public_keys)
  end

  @doc """
  Lists SSH usernames for a specific node with preloaded public keys.
  """
  def list_ssh_usernames_for_node(node_id) do
    from(u in SshUsername,
      where: u.node_id == ^node_id,
      preload: [:ssh_public_keys],
      order_by: [desc: u.inserted_at]
    )
    |> Repo.all()
  end

  def create_ssh_username(attrs \\ %{}) do
    %SshUsername{}
    |> SshUsername.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an SSH username with optional public keys in a transaction.

  attrs format:
  %{
    username: "deploy",
    password: "secret123",  # Optional
    node_id: "uuid",
    public_keys: [  # Optional
      %{key_name: "laptop", public_key: "ssh-rsa AAA..."},
      %{key_name: "ci", public_key: "ssh-rsa BBB..."}
    ]
  }
  """
  def create_ssh_username_with_keys(attrs) do
    Repo.transaction(fn ->
      # Handle both string and atom keys for public_keys
      {public_keys_attrs, username_attrs} =
        Map.pop(attrs, "public_keys") || Map.pop(attrs, :public_keys, [])

      public_keys_attrs = public_keys_attrs || []

      # Create username
      case create_ssh_username(username_attrs) do
        {:ok, username} ->
          # Create public keys if provided
          keys =
            Enum.map(public_keys_attrs, fn key_attrs ->
              # Ensure ssh_username_id is set (use string key to avoid mixed keys)
              key_attrs = Map.put(key_attrs, "ssh_username_id", username.id)

              case create_ssh_public_key(key_attrs) do
                {:ok, key} -> key
                {:error, changeset} -> Repo.rollback(changeset)
              end
            end)

          # Return username with loaded keys
          %{username | ssh_public_keys: keys}

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def delete_ssh_username(%SshUsername{} = ssh_username) do
    Repo.delete(ssh_username)
  end

  def change_ssh_username(%SshUsername{} = ssh_username, attrs \\ %{}) do
    SshUsername.changeset(ssh_username, attrs)
  end

  def list_ssh_usernames_with_filtering_pagination(params \\ %{}) do
    FilteringPagination.paginate(
      SshUsername,
      params,
      filterable_fields: [:username, :node_id],
      sortable_fields: [:inserted_at, :updated_at, :username],
      default_sort: "inserted_at:desc",
      repo: Repo,
      preload: [:ssh_public_keys]
    )
  end

  def get_ssh_public_key!(id), do: Repo.get!(SshPublicKey, id)

  def create_ssh_public_key(attrs \\ %{}) do
    %SshPublicKey{}
    |> SshPublicKey.changeset(attrs)
    |> Repo.insert()
  end

  def update_ssh_public_key(%SshPublicKey{} = ssh_public_key, attrs) do
    ssh_public_key
    |> SshPublicKey.changeset(attrs)
    |> Repo.update()
  end

  def delete_ssh_public_key(%SshPublicKey{} = ssh_public_key) do
    Repo.delete(ssh_public_key)
  end

  def change_ssh_public_key(%SshPublicKey{} = ssh_public_key, attrs \\ %{}) do
    SshPublicKey.changeset(ssh_public_key, attrs)
  end

  def list_ssh_public_keys_with_filtering_pagination(params \\ %{}) do
    FilteringPagination.paginate(
      SshPublicKey,
      params,
      filterable_fields: [:key_name, :ssh_username_id],
      sortable_fields: [:inserted_at, :updated_at, :key_name],
      default_sort: "inserted_at:desc",
      repo: Repo
    )
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

  ### Ephemeral
  Creates a tracked key for automatic cleanup after TTL.
  - Configurable expiration (default: 1 hour)
  - Configurable uses (default: 1)
  - Tracked in DB for auto-cleanup
  - Use for: Temporary troubleshooting, testing, demos
  """
  def create_enrollment_key(cluster_name, attrs \\ %{}) do
    # Parse parameters
    key_type = Map.get(attrs, :key_type, Map.get(attrs, "key_type", "default"))
    expiration = Map.get(attrs, :expiration, Map.get(attrs, "expiration", 3600))  # Default 1 hour
    uses_remaining = Map.get(attrs, :uses_remaining, Map.get(attrs, "uses_remaining", 1))  # Default single use

    # Validate key_type
    if key_type not in ["default", "custom", "ephemeral"] do
      {:error, "key_type must be 'default', 'custom', or 'ephemeral'"}
    else
      # Get cluster by name
      cluster = get_cluster!(cluster_name)
      network_name = Vpn.build_network_name(cluster.name, prefix: :node)

      case key_type do
        "default" ->
          # Retrieve the default key from Netmaker (created automatically with network)
          case Vpn.get_default_enrollment_key(network_name) do
            {:ok, token} ->
              {:ok, %{token: token, key_type: "default"}}

            {:error, reason} ->
              {:error, reason}
          end

        "custom" ->
          # Create a custom key with user-specified expiry/uses
          # Generate tag for audit trail (not tracked in DB)
          timestamp = System.system_time(:millisecond)
          random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
          tag = "custom-#{timestamp}-#{random}"

          case Vpn.create_enrollment_key(network_name, %{
                 expiration: expiration,
                 uses_remaining: uses_remaining,
                 tags: [tag]
               }) do
            {:ok, netmaker_key} ->
              {:ok, %{token: netmaker_key["token"], key_type: "custom"}}

            {:error, reason} ->
              {:error, reason}
          end

        "ephemeral" ->
          # Create ephemeral key tracked in DB for automatic cleanup
          Repo.transaction(fn ->
            # Generate unique tag for this key
            timestamp = System.system_time(:millisecond)
            random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
            tag = "ephemeral-#{timestamp}-#{random}"

            case Vpn.create_enrollment_key(network_name, %{
                   expiration: expiration,
                   uses_remaining: uses_remaining,
                   tags: [tag]
                 }) do
              {:ok, netmaker_key} ->
                token = netmaker_key["token"]

                # Track in DB for cleanup (store tag for later queries)
                case %EphemeralEnrollmentKey{}
                     |> EphemeralEnrollmentKey.changeset(%{
                       token: token,
                       tag: tag,
                       cluster_id: cluster.id
                     })
                     |> Repo.insert() do
                  {:ok, _} ->
                    %{token: token, key_type: "ephemeral"}

                  {:error, changeset} ->
                    Repo.rollback(changeset)
                end

              {:error, reason} ->
                Repo.rollback(reason)
            end
          end)
      end
    end
  end

  @doc """
  Cleans up expired ephemeral enrollment keys and their associated resources.

  This function:
  1. Finds expired ephemeral enrollment keys (inserted_at < cutoff_time)
  2. For each expired key:
     - Queries Netmaker for hosts enrolled with this key
     - Deletes Netmaker hosts (both staff and ephemeral edge nodes)
     - Deletes our DB nodes (ephemeral edge nodes only, staff don't register)
     - Deletes the enrollment key from Netmaker (for database hygiene)
     - Deletes the ephemeral enrollment key tracker from our DB
  3. All operations for each key are wrapped in a transaction - if ANY deletion fails,
     the entire key cleanup is rolled back (except Netmaker key deletion which is best-effort)

  Returns statistics about the cleanup operation.
  """
  def cleanup_ephemeral_keys do
    ttl_hours = Application.get_env(:edge_admin, :ephemeral_key_ttl_hours, 168)
    cutoff_time = DateTime.add(DateTime.utc_now(), -ttl_hours * 3600, :second)

    # Find expired tracked keys
    expired_keys =
      from(ek in EphemeralEnrollmentKey,
        where: ek.inserted_at < ^cutoff_time,
        preload: [:cluster]
      )
      |> Repo.all()

    Logger.info("Found #{length(expired_keys)} expired ephemeral enrollment keys")

    result = %{
      deleted_keys: 0,
      deleted_hosts: 0,
      deleted_nodes: 0
    }

    # Process each expired key
    Enum.reduce(expired_keys, result, fn enrollment_key, acc ->
      cleanup_enrollment_key(enrollment_key, acc)
    end)
  end

  defp cleanup_enrollment_key(enrollment_key, acc) do
    Logger.debug("Processing expired key: #{enrollment_key.token} with tag: #{enrollment_key.tag}")

    # Wrap entire cleanup in transaction - rollback everything if ANY step fails
    case Repo.transaction(fn ->
           # 1. Query Netmaker for nodes using this tag
           network_name = Vpn.build_network_name(enrollment_key.cluster.name, prefix: :node)

           netmaker_nodes =
             case Vpn.list_nodes_by_tag(enrollment_key.tag) do
               {:ok, nodes} -> nodes
               {:error, reason} ->
                 Logger.warning(
                   "Failed to query nodes by tag #{enrollment_key.tag}: #{inspect(reason)}"
                 )
                 []
             end

           # Extract unique host IDs from nodes
           host_ids =
             netmaker_nodes
             |> Enum.map(& &1["hostid"])
             |> Enum.uniq()
             |> Enum.reject(&is_nil/1)

           Logger.debug("Found #{length(host_ids)} unique hosts with tag #{enrollment_key.tag}")

           # 2. Delete each Netmaker host (treat "not found" as success for idempotency)
           Enum.each(host_ids, fn host_id ->
             case Vpn.delete_host(network_name, host_id) do
               {:ok, _} ->
                 Logger.info(
                   "Deleted Netmaker host #{host_id} from cluster #{enrollment_key.cluster.name}"
                 )

               {:error, {:http_error, 500, body}} = error ->
                 if netmaker_not_found_error?(body) do
                   Logger.info(
                     "Netmaker host #{host_id} already deleted (not found)"
                   )
                 else
                   Logger.error("Failed to delete host #{host_id}: #{inspect(error)}")
                   Repo.rollback(error)
                 end

               {:error, reason} ->
                 Logger.error("Failed to delete host #{host_id}: #{inspect(reason)}")
                 Repo.rollback(reason)
             end
           end)

           # 3. Delete our DB nodes associated with these hosts (if they exist)
           #    Staff users won't have entries here, ephemeral edge nodes will
           {deleted_nodes, _} =
             from(n in Node, where: n.netmaker_host_id in ^host_ids)
             |> Repo.delete_all()

           if deleted_nodes > 0 do
             Logger.info(
               "Deleted #{deleted_nodes} ephemeral edge node(s) from DB (netmaker_host_id in #{inspect(host_ids)})"
             )
           end

           # 4. Delete the enrollment key from Netmaker
           case Vpn.delete_enrollment_key(enrollment_key.token) do
             {:ok, _} ->
               Logger.info("Deleted enrollment key from Netmaker: #{enrollment_key.token}")

             {:error, reason} ->
               # Log but don't fail - key might already be deleted
               Logger.warning(
                 "Failed to delete enrollment key from Netmaker (might not exist): #{inspect(reason)}"
               )
           end

           # 5. Delete the ephemeral enrollment key tracker from our DB
           Repo.delete!(enrollment_key)
           Logger.debug("Deleted ephemeral enrollment key tracker: #{enrollment_key.id}")

           # Return stats for this key
           %{
             deleted_hosts: length(host_ids),
             deleted_nodes: deleted_nodes
           }
         end) do
      {:ok, stats} ->
        # Transaction succeeded - update accumulator
        %{
          deleted_keys: acc.deleted_keys + 1,
          deleted_hosts: acc.deleted_hosts + stats.deleted_hosts,
          deleted_nodes: acc.deleted_nodes + stats.deleted_nodes
        }

      {:error, reason} ->
        # Transaction failed - log and skip this key
        Logger.error(
          "Transaction failed for ephemeral key #{enrollment_key.token}: #{inspect(reason)}"
        )

        acc
    end
  end

  # Helper to check if Netmaker error is a "not found" error
  # Netmaker uses HTTP 500 with specific messages for not found
  defp netmaker_not_found_error?(body) when is_binary(body) do
    String.contains?(body, "no result found") or
      String.contains?(body, "could not find any records")
  end

  defp netmaker_not_found_error?(body) when is_map(body) do
    message = Map.get(body, "Message", "")
    String.contains?(message, "no result found") or
      String.contains?(message, "could not find any records")
  end

  defp netmaker_not_found_error?(_), do: false

  @doc """
  Reconciles cluster node membership between database (source of truth) and Netmaker.

  For each cluster:
  1. Gets nodes that SHOULD be in the network (from DB)
  2. Gets nodes that ARE in the network (from Netmaker)
  3. Cleans up orphaned aliases (nodes not in DB or not in Netmaker)
  4. Adds missing nodes (DB says yes, Netmaker says no)
  5. Removes extra nodes (Netmaker says yes, DB says no)

  Only processes edge nodes (those belonging to edge agents, identified by having a DB record).
  Admin nodes and staff machines are not touched.

  Returns statistics about the reconciliation operation.
  """
  def reconcile_cluster_nodes do
    clusters = list_clusters()

    # Get all DB nodes grouped by cluster
    db_nodes_by_cluster =
      from(n in Node, preload: [:cluster])
      |> Repo.all()
      |> Enum.group_by(& &1.cluster_id)

    Logger.info("Starting cluster reconciliation for #{length(clusters)} clusters")

    result = %{
      clusters_processed: 0,
      nodes_added: 0,
      nodes_removed: 0,
      aliases_cleaned: 0,
      errors: 0
    }

    Enum.reduce(clusters, result, fn cluster, acc ->
      reconcile_single_cluster(cluster, db_nodes_by_cluster[cluster.id] || [], acc)
    end)
  end

  defp reconcile_single_cluster(cluster, db_nodes, acc) do
    network_name = Vpn.build_network_name(cluster.name, prefix: :node)

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

        # Find edge node host IDs in Netmaker (those we have in DB)
        # This filters out admin nodes and staff machines
        edge_node_host_ids = MapSet.intersection(actual_host_ids, expected_host_ids)

        # Clean up orphaned aliases for nodes not in both DB and Netmaker
        # These are nodes that either: left the network, were deleted, or moved clusters
        orphaned_host_ids = MapSet.difference(expected_host_ids, edge_node_host_ids)
        orphaned_nodes = Enum.filter(db_nodes, fn node -> node.netmaker_host_id in orphaned_host_ids end)
        aliases_cleaned = cleanup_orphaned_aliases(orphaned_nodes)

        # Add missing nodes (DB says yes, Netmaker says no)
        missing = MapSet.difference(expected_host_ids, edge_node_host_ids)
        added = add_missing_nodes(missing, network_name, cluster.name)

        # Remove extra nodes (Netmaker says yes for our edge nodes, but DB says no)
        # Only remove edge nodes that we manage (exist in our DB or used to exist)
        extra = MapSet.difference(edge_node_host_ids, expected_host_ids)
        removed = remove_extra_nodes(extra, network_name, cluster.name)

        %{
          clusters_processed: acc.clusters_processed + 1,
          nodes_added: acc.nodes_added + added,
          nodes_removed: acc.nodes_removed + removed,
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
          Logger.warning("Reconciliation: Failed to remove host #{host_id} from network #{network_name}: #{inspect(reason)}")
          count
      end
    end)
  end

  @doc """
  Cleans up all aliases for a single node.

  Deletes DNS entries from Netmaker and removes alias records from DB.
  Best-effort - logs warnings on failures but continues cleanup.

  Used when a node changes clusters (all aliases become invalid).
  """
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
    network_name = Vpn.build_network_name(alias_record.cluster.name, prefix: :node)
    dns_hostname = Alias.dns_hostname(alias_record)

    # 1. Try to delete DNS entry (best-effort)
    case Nexmaker.Api.DNS.delete(network_name, dns_hostname) do
      {:ok, _} ->
        Logger.info("Deleted DNS entry for alias #{alias_record.name}: #{dns_hostname}")

      {:error, {:http_error, 500, body}} ->
        # Netmaker returns 500 for "not found" - treat as already deleted
        if String.contains?(body, "no result found") or
             String.contains?(body, "could not find any records") do
          Logger.debug("DNS entry already deleted for alias #{alias_record.name}: #{dns_hostname}")
        else
          Logger.warning("Failed to delete DNS entry for alias #{alias_record.name}: #{inspect(body)}")
        end

      {:error, reason} ->
        Logger.warning("Failed to delete DNS entry for alias #{alias_record.name}: #{inspect(reason)}")
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
  - `name` - Text search
  - `cluster_name` - Exact match on cluster name
  - `node_id` - Exact match on node ID
  """
  def list_aliases_with_filtering_pagination(params \\ %{}) do
    # Handle cluster_name filter specially (join-based)
    {cluster_name_filter, other_params} = Map.pop(params, "cluster_name")

    base_query =
      from(a in Alias,
        join: c in assoc(a, :cluster),
        preload: [cluster: c]
      )

    # Apply cluster_name filter if present
    query_with_cluster_filter =
      if cluster_name_filter do
        from([a, c] in base_query, where: c.name == ^cluster_name_filter)
      else
        base_query
      end

    # Use FilteringPagination for the rest
    result =
      FilteringPagination.paginate(
        query_with_cluster_filter,
        other_params,
        filterable_fields: [:name, :node_id],
        sortable_fields: [:inserted_at, :updated_at, :name],
        default_sort: "inserted_at:desc",
        repo: Repo
      )

    # Re-add cluster_name to filters if it was present
    if cluster_name_filter do
      %{result | filters: Map.put(result.filters, "cluster_name", cluster_name_filter)}
    else
      result
    end
  end

  @doc """
  Gets a single alias by ID.
  Raises `Ecto.NoResultsError` if not found.
  """
  def get_alias!(id) do
    Alias
    |> Repo.get!(id)
    |> Repo.preload(:cluster)
  end

  @doc """
  Creates an alias for a node.

  Flow:
  1. Verify node exists and preload cluster
  2. Query Netmaker for node's IP address
  3. Create DNS entry in Netmaker
  4. Insert alias into DB

  If any step fails, the entire operation is rolled back.
  """
  def create_alias(%Node{} = node, attrs) do
    Repo.transaction(fn ->
      # 1. Ensure node has cluster preloaded
      node = Repo.preload(node, :cluster)

      # 2. Build attrs with cluster_id
      alias_attrs = Map.merge(attrs, %{
        "node_id" => node.id,
        "cluster_id" => node.cluster_id
      })

      # 3. Validate with changeset first
      changeset = Alias.changeset(%Alias{}, alias_attrs)

      case Repo.insert(changeset) do
        {:ok, alias_record} ->
          # 4. Preload cluster for virtual fields
          alias_record = Repo.preload(alias_record, :cluster)

          # 5. Query Netmaker for node's IP address
          network_name = Vpn.build_network_name(node.cluster.name, prefix: :node)

          case Vpn.list_nodes(network_name) do
            {:ok, netmaker_nodes} ->
              # Find node by hostid
              netmaker_node =
                Enum.find(netmaker_nodes, fn n ->
                  n["hostid"] == node.netmaker_host_id
                end)

              case netmaker_node do
                nil ->
                  Repo.rollback(:node_not_found_in_netmaker)

                %{"address" => address} when is_binary(address) and address != "" ->
                  # 6. Create DNS entry in Netmaker
                  # Strip CIDR suffix if present (e.g., "100.64.1.5/32" -> "100.64.1.5")
                  ip_address = address |> String.split("/") |> List.first()
                  dns_hostname = Alias.dns_hostname(alias_record)

                  case Nexmaker.Api.DNS.create(network_name, %{
                         name: dns_hostname,
                         address: ip_address
                       }) do
                    {:ok, _} ->
                      Logger.info(
                        "Created DNS entry for alias #{alias_record.name}: #{dns_hostname} -> #{address}"
                      )

                      alias_record

                    {:error, reason} ->
                      Logger.error("Failed to create DNS entry: #{inspect(reason)}")
                      Repo.rollback(reason)
                  end

                _ ->
                  Repo.rollback(:node_has_no_ip_address)
              end

            {:error, reason} ->
              Logger.error("Failed to list Netmaker nodes: #{inspect(reason)}")
              Repo.rollback(reason)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Deletes an alias.

  Flow:
  1. Delete DNS entry from Netmaker
  2. Delete alias from DB

  If DNS deletion fails, the entire operation is rolled back.
  """
  def delete_alias(%Alias{} = alias_record) do
    Repo.transaction(fn ->
      # 1. Ensure cluster is preloaded
      alias_record = Repo.preload(alias_record, :cluster)

      # 2. Delete DNS entry from Netmaker
      network_name = Vpn.build_network_name(alias_record.cluster.name, prefix: :node)
      dns_hostname = Alias.dns_hostname(alias_record)

      case Nexmaker.Api.DNS.delete(network_name, dns_hostname) do
        {:ok, _} ->
          Logger.info("Deleted DNS entry for alias #{alias_record.name}: #{dns_hostname}")

          # 3. Delete from DB
          Repo.delete!(alias_record)

        {:error, {:http_error, 500, body}} = error ->
          # Netmaker returns 500 for "not found" - treat as success for idempotency
          if String.contains?(body, "no result found") or
               String.contains?(body, "could not find any records") do
            Logger.info("DNS entry already deleted for alias #{alias_record.name}: #{dns_hostname}")
            Repo.delete!(alias_record)
          else
            Logger.error("Failed to delete DNS entry: #{inspect(error)}")
            Repo.rollback(error)
          end

        {:error, reason} ->
          Logger.error("Failed to delete DNS entry: #{inspect(reason)}")
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking alias changes.
  """
  def change_alias(%Alias{} = alias_record, attrs \\ %{}) do
    Alias.changeset(alias_record, attrs)
  end

  def list_metrics_discovery_targets do
    from(n in Node,
      where: not is_nil(n.vpn_ip) and n.vpn_ip != "",
      select: n.vpn_ip
    )
    |> Repo.all()
    |> Enum.map(&"#{&1}:9100")
  end

  def list_node_metrics(node_id) do
    with {:ok, node} <- get_node_result(node_id),
         {:ok, raw_metrics} <- fetch_current_node_metrics(node),
         {:ok, metrics} <- build_validated_metrics(raw_metrics, node_id) do
      {:ok, metrics}
    else
      {:error, :not_found} -> {:error, :node_not_found}
      {:error, :no_vpn_ip} -> {:error, :metrics_unavailable}
      {:error, :metrics_service_not_configured} -> {:error, :metrics_unavailable}
      {:error, :metrics_service_unavailable} -> {:error, :metrics_unavailable}
      {:error, %Ecto.Changeset{}} = changeset_error -> changeset_error
      {:error, _reason} -> {:error, :metrics_unavailable}
    end
  end

  defp get_node_result(node_id) do
    {:ok, get_node!(node_id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp fetch_current_node_metrics(%Node{cluster_id: nil}), do: {:error, :no_cluster}

  defp fetch_current_node_metrics(%Node{} = node) do
    base_url = Application.get_env(:edge_admin, :metrics_storage_url)

    # Add validation for missing config
    if is_nil(base_url) or base_url == "" do
      {:error, :metrics_service_not_configured}
    else
      # Use DNS hostname and metrics_port instead of vpn_ip
      dns_hostname = Node.dns_hostname(node)
      instance = "#{dns_hostname}:#{node.metrics_port}"

      queries = [
        # CPU metrics
        {"cpu_usage_percent",
         "100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\",instance=\"#{instance}\"}[5m])) * 100)"},
        {"cpu_cores", "count(count(node_cpu_seconds_total{instance=\"#{instance}\"}) by (cpu))"},
        {"load_1m", "node_load1{instance=\"#{instance}\"}"},
        {"load_5m", "node_load5{instance=\"#{instance}\"}"},
        {"load_15m", "node_load15{instance=\"#{instance}\"}"},

        # Memory metrics
        {"memory_total_bytes", "node_memory_MemTotal_bytes{instance=\"#{instance}\"}"},
        {"memory_available_bytes", "node_memory_MemAvailable_bytes{instance=\"#{instance}\"}"},
        {"memory_usage_percent",
         "(1 - (node_memory_MemAvailable_bytes{instance=\"#{instance}\"} / node_memory_MemTotal_bytes{instance=\"#{instance}\"})) * 100"},

        # Disk metrics (root filesystem)
        {"disk_total_bytes",
         "node_filesystem_size_bytes{instance=\"#{instance}\",mountpoint=\"/\"}"},
        {"disk_available_bytes",
         "node_filesystem_avail_bytes{instance=\"#{instance}\",mountpoint=\"/\"}"},
        {"disk_usage_percent",
         "100 - ((node_filesystem_avail_bytes{instance=\"#{instance}\",mountpoint=\"/\"} * 100) / node_filesystem_size_bytes{instance=\"#{instance}\",mountpoint=\"/\"})"},

        # Network metrics (rate over 5 minutes, excluding loopback)
        {"network_rx_bytes_per_sec",
         "sum(rate(node_network_receive_bytes_total{instance=\"#{instance}\",device!=\"lo\"}[5m]))"},
        {"network_tx_bytes_per_sec",
         "sum(rate(node_network_transmit_bytes_total{instance=\"#{instance}\",device!=\"lo\"}[5m]))"},
        {"network_rx_packets_per_sec",
         "sum(rate(node_network_receive_packets_total{instance=\"#{instance}\",device!=\"lo\"}[5m]))"},
        {"network_tx_packets_per_sec",
         "sum(rate(node_network_transmit_packets_total{instance=\"#{instance}\",device!=\"lo\"}[5m]))"},

        # Uptime
        {"uptime_seconds",
         "node_time_seconds{instance=\"#{instance}\"} - node_boot_time_seconds{instance=\"#{instance}\"}"}
      ]

      try do
        raw_metrics = query_all_metrics(base_url, queries)
        {:ok, raw_metrics}
      rescue
        _ -> {:error, :metrics_service_unavailable}
      catch
        _ -> {:error, :metrics_service_unavailable}
      end
    end
  end

  defp build_validated_metrics(raw_metrics, node_id) do
    metrics = Metrics.from_raw_metrics(raw_metrics, node_id)
    {:ok, metrics}
  rescue
    Ecto.InvalidChangesetError ->
      {:error, :invalid_metrics_data}
  catch
    {:error, %Ecto.Changeset{}} = error -> error
  end

  defp query_all_metrics(base_url, queries) do
    Enum.reduce(queries, %{}, fn {key, query}, acc ->
      case query_victoria_metrics(base_url, query) do
        {:ok, value} -> Map.put(acc, key, value)
        {:error, _} -> Map.put(acc, key, nil)
      end
    end)
  end

  defp query_victoria_metrics(base_url, query) do
    url = "#{base_url}/api/v1/query"

    case Req.get(url, params: [query: query]) do
      {:ok,
       %{
         status: 200,
         body: %{
           "status" => "success",
           "data" => %{"result" => [%{"value" => [_timestamp, value]} | _]}
         }
       }} ->
        case Float.parse(value) do
          {float_value, _} -> {:ok, float_value}
          :error -> {:error, :invalid_number}
        end

      {:ok, %{status: 200, body: %{"status" => "success", "data" => %{"result" => []}}}} ->
        {:error, :no_data}

      _ ->
        {:error, :query_failed}
    end
  end
end
