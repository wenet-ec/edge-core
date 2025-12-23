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
  alias EdgeAdmin.Nodes.Forms
  alias EdgeAdmin.Nodes.Metrics
  alias EdgeAdmin.Nodes.Node
  alias EdgeAdmin.Nodes.SshPublicKey
  alias EdgeAdmin.Nodes.SshUsername
  alias EdgeAdmin.Repo
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
  - `ipv4_range` - Text search (e.g., "100.64.1")
  - `node_count` - Range queries (e.g., "gte:5", "lt:10", "0")

  Supports sorting by:
  - `inserted_at`, `updated_at`, `ipv4_range`, `node_count`
  """
  def list_clusters_with_filtering_pagination(params \\ %{}) do
    # Extract node_count filter to handle separately
    {node_count_filter, other_params} = Map.pop(params, "node_count")

    base_query =
      if node_count_filter do
        # Need to compute count for HAVING clause when filtering
        from(c in Cluster,
          left_join: n in assoc(c, :nodes),
          group_by: c.id,
          select_merge: %{node_count: count(n.id)}
        )
        |> apply_node_count_filter(node_count_filter)
      else
        # No filter, just use base Cluster query
        Cluster
      end

    # Use FilteringPagination for the rest
    result =
      FilteringPagination.paginate(
        base_query,
        other_params,
        filterable_fields: [:ipv4_range],
        sortable_fields: [:inserted_at, :updated_at, :ipv4_range],
        default_sort: "inserted_at:desc",
        repo: Repo,
        preload: :nodes
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
  Lists all clusters with nodes preloaded (no pagination).
  """
  def list_clusters do
    from(c in Cluster,
      order_by: [desc: c.inserted_at],
      preload: :nodes
    )
    |> Repo.all()
  end

  @doc """
  Gets a single cluster by name.

  ## Returns
  - `{:ok, cluster}` - Cluster found
  - `{:error, :not_found}` - Cluster does not exist
  """
  def get_cluster(name) do
    case Repo.get_by(Cluster, name: name) do
      nil -> {:error, :not_found}
      cluster -> {:ok, Repo.preload(cluster, :nodes)}
    end
  end

  @doc """
  Creates a cluster with automatic name/IP range generation and Netmaker network creation.

  ## Parameters
  - `attrs` - Cluster creation parameters (validated through CreateClusterForm)

  ## Returns
  - `{:ok, cluster}` - Cluster created successfully
  - `{:error, changeset}` - Validation or creation failed
  """
  def create_cluster(attrs \\ %{}) do
    with {:ok, validated_attrs} <- Forms.CreateClusterForm.changeset(attrs) do
      # 1. Auto-generate IP range if not provided
      existing_ranges = Repo.all(from(c in Cluster, select: c.ipv4_range))
      ipv4_range = validated_attrs["ipv4_range"] || Vpn.generate_next_subnet(existing_ranges)

      # 2. Merge IP range into attrs
      cluster_attrs = Map.put(validated_attrs, "ipv4_range", ipv4_range)

      # 3. Create temporary cluster record to get name (for network name generation)
      temp_changeset = Cluster.changeset(%Cluster{}, cluster_attrs)

      case Ecto.Changeset.apply_action(temp_changeset, :insert) do
        {:ok, temp_cluster} ->
          # 4. Create Netmaker network FIRST
          network_name = node_network_name(temp_cluster)

          case Vpn.create_network(network_name, %{addressrange: ipv4_range}) do
            {:ok, _} ->
              # 5. Create cluster in DB (source of truth)
              case %Cluster{}
                   |> Cluster.changeset(cluster_attrs)
                   |> Repo.insert() do
                {:ok, cluster} ->
                  # 6. Broadcast cluster creation event to all admins in this admin cluster
                  broadcast_metadata_event({:cluster_created, cluster.id})

                  {:ok, cluster}

                {:error, changeset} ->
                  # Cleanup: Delete Netmaker network if DB insert fails
                  Logger.warning(
                    "Failed to create cluster in DB, cleaning up Netmaker network #{network_name}"
                  )

                  Vpn.delete_network(network_name)
                  {:error, changeset}
              end

            {:error, reason} ->
              {:error, reason}
          end

        {:error, changeset} ->
          {:error, changeset}
      end
    end
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

  Flow:
  1. Verify cluster is empty
  2. Delete Netmaker network first
  3. Delete from DB (source of truth)
  4. Emit event for metadata recomputation

  If Netmaker deletion fails, DB deletion is skipped.
  If DB deletion fails after Netmaker succeeds, reconciliation will clean up the orphaned cluster.
  """
  def delete_cluster(%Cluster{} = cluster) do
    # 1. Verify cluster is empty (DB constraint also enforces this)
    node_count = Repo.aggregate(from(n in Node, where: n.cluster_id == ^cluster.id), :count)

    if node_count > 0 do
      {:error, "Cannot delete cluster with nodes. Remove all nodes first."}
    else
      # 2. Delete Netmaker network FIRST
      network_name = node_network_name(cluster)

      case Vpn.delete_network(network_name) do
        {:ok, _} ->
          # 3. Delete from DB (source of truth)
          case Repo.delete(cluster) do
            {:ok, deleted_cluster} ->
              # 4. Broadcast cluster deletion event to all admins in this admin cluster
              broadcast_metadata_event({:cluster_deleted, cluster.id})

              {:ok, deleted_cluster}

            {:error, changeset} ->
              Logger.error(
                "Failed to delete cluster #{cluster.id} from DB after Netmaker deletion. Reconciliation will clean up."
              )

              {:error, changeset}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
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

  @doc """
  Gets a single node by ID.

  ## Returns
  - `{:ok, node}` - Node found with cluster and aliases preloaded
  - `{:error, :not_found}` - Node does not exist or invalid UUID format
  """
  def get_node(id) do
    case Repo.get(Node, id) do
      nil -> {:error, :not_found}
      node -> {:ok, Repo.preload(node, [:cluster, aliases: :cluster])}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
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

  ## Parameters
  - `node` - The node struct to move
  - `params` - Request params containing new cluster name (validated through ChangeNodeClusterForm)

  ## Returns
  - `{:ok, updated_node}` - Node cluster changed successfully
  - `{:error, changeset}` - Validation failed
  """
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
          updated_node = Repo.preload(updated_node, :cluster, force: true)

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
                  Logger.info(
                    "Removed host #{node.netmaker_host_id} from network #{old_network_name}"
                  )

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

  Flow:
  1. Delete all DNS records (aliases) from Netmaker first
  2. Delete host from Netmaker (removes from all networks)
  3. Delete from DB (cascades to ssh_usernames, ssh_public_keys, command_executions, aliases)
  4. Emit event for metadata recomputation

  If Netmaker deletion fails, DB deletion is skipped.
  If DB deletion fails after Netmaker succeeds, reconciliation will clean up the orphaned node.
  """
  def delete_node(%Node{} = node) do
    # 1. Clean up DNS records (aliases) from Netmaker FIRST
    # Best-effort - logs warnings on failures but continues
    cleanup_node_aliases(node)

    # 2. Delete host from Netmaker (removes from all networks)
    case Vpn.delete_host(node.netmaker_host_id) do
      {:ok, _} ->
        Logger.info("Deleted host #{node.netmaker_host_id} from Netmaker")

        # 3. Delete from DB (cascades to ssh_usernames, ssh_public_keys, command_executions, aliases)
        case Repo.delete(node) do
          {:ok, deleted_node} ->
            # 4. Emit PubSub event for metadata recomputation
            broadcast_metadata_event({:node_deleted, node.id, node.cluster_id})

            {:ok, deleted_node}

          {:error, changeset} ->
            Logger.error(
              "Failed to delete node #{node.id} from DB after Netmaker deletion. Reconciliation will clean up."
            )

            {:error, changeset}
        end

      {:error, reason} ->
        Logger.error("Failed to delete host from Netmaker: #{inspect(reason)}")
        {:error, reason}
    end
  end

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

      Logger.debug(
        "Starting health check for #{length(nodes)} nodes (concurrency: #{concurrency}, timeout: #{timeout}ms)"
      )

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
  def list_node_identifiers_by_cluster(cluster_name) do
    case get_cluster(cluster_name) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, cluster} ->
        nodes =
          from(n in Node,
            where: n.cluster_id == ^cluster.id,
            preload: [:cluster, aliases: :cluster]
          )
          |> Repo.all()

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

  def get_ssh_username(id) do
    case Repo.get(SshUsername, id) do
      nil -> {:error, :not_found}
      ssh_username -> {:ok, Repo.preload(ssh_username, :ssh_public_keys)}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  @doc """
  Gets a specific SSH username for a node with preloaded public keys.
  Used by agents for credential verification.
  """
  def get_ssh_username_for_node(node_id, username) do
    from(u in SshUsername,
      where: u.node_id == ^node_id and u.username == ^username,
      preload: [:ssh_public_keys]
    )
    |> Repo.one()
  end

  def create_ssh_username(attrs \\ %{}) do
    %SshUsername{}
    |> SshUsername.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an SSH username with optional public keys in a transaction.

  ## Parameters
  - `node` - The node struct (validated in controller via path param)
  - `params` - Request params (validated through CreateSshUsernameForm)

  ## Returns
  - `{:ok, ssh_username}` - SSH username created successfully with keys loaded
  - `{:error, changeset}` - Validation or creation failed
  """
  def create_ssh_username_with_keys(%Node{} = node, params) do
    with {:ok, attrs} <- Forms.CreateSshUsernameForm.changeset(params) do
      # Extract public_keys (if present) and prepare username attrs
      {public_keys_attrs, username_attrs} = Map.pop(attrs, "public_keys", [])

      # Hash password if provided
      username_attrs =
        case Map.get(username_attrs, "password") do
          nil ->
            username_attrs

          password when is_binary(password) ->
            username_attrs
            |> Map.delete("password")
            |> Map.put("password_hash", Argon2.hash_pwd_salt(password))
        end

      username_attrs = Map.put(username_attrs, "node_id", node.id)

      # Create username
      case create_ssh_username(username_attrs) do
        {:ok, username} ->
          # Create public keys (already validated by CreateSshUsernameForm, fail silently on DB errors)
          keys =
            Enum.flat_map(public_keys_attrs, fn key_attrs ->
              key_attrs = Map.put(key_attrs, "ssh_username_id", username.id)

              case insert_ssh_public_key(key_attrs) do
                {:ok, key} -> [key]
                {:error, _changeset} -> []
              end
            end)

          # Return username with loaded keys (only successfully created keys)
          {:ok, %{username | ssh_public_keys: keys}}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  def delete_ssh_username(%SshUsername{} = ssh_username) do
    Repo.delete(ssh_username)
  end

  def change_ssh_username(%SshUsername{} = ssh_username, attrs \\ %{}) do
    SshUsername.changeset(ssh_username, attrs)
  end

  @doc """
  Verifies SSH credentials (password or public key) for a given node and username.

  Used by agents to validate SSH authentication attempts. Does not distinguish
  between "username not found" and "incorrect credential" for security reasons.

  ## Parameters
  - `node_id` - The node ID (from agent's API token)
  - `params` - Request params containing username and either password or public_key

  ## Returns
  - `{:ok, true}` - Credential verified successfully
  - `{:ok, false}` - Username not found or credential incorrect
  - `{:error, changeset}` - Validation failed
  """
  def verify_ssh_credentials(node_id, params) do
    with {:ok, attrs} <- Forms.VerifySshCredentialsForm.changeset(params) do
      username = Map.get(attrs, "username")
      password = Map.get(attrs, "password")
      public_key = Map.get(attrs, "public_key")

      # Query SSH username for this node (with preloaded public keys)
      ssh_username = get_ssh_username_for_node(node_id, username)

      verified =
        case {ssh_username, password, public_key} do
          {nil, _, _} ->
            # Username not found - return false (don't leak this info)
            false

          {%SshUsername{password_hash: nil}, password, _} when not is_nil(password) ->
            # Password auth requested but no password configured
            false

          {%SshUsername{password_hash: hash}, password, _} when not is_nil(password) ->
            # Verify password with Argon2
            Argon2.verify_pass(password, hash)

          {%SshUsername{ssh_public_keys: []}, _, public_key} when not is_nil(public_key) ->
            # Public key auth requested but no keys configured
            false

          {%SshUsername{ssh_public_keys: keys}, _, public_key} when not is_nil(public_key) ->
            # Verify public key - normalize and compare
            provided_key_normalized = normalize_ssh_key(public_key)

            Enum.any?(keys, fn stored_key ->
              stored_key_normalized =
                stored_key.public_key
                |> String.trim()
                |> normalize_ssh_key()

              provided_key_normalized == stored_key_normalized
            end)
        end

      {:ok, verified}
    end
  end

  # Normalizes SSH key by removing comment (keeps algorithm + key data only)
  defp normalize_ssh_key(key_string) do
    case String.split(key_string, " ", parts: 3) do
      [algorithm, key_data, _comment] -> "#{algorithm} #{key_data}"
      [algorithm, key_data] -> "#{algorithm} #{key_data}"
      _ -> String.trim(key_string)
    end
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

  def get_ssh_public_key(id) do
    case Repo.get(SshPublicKey, id) do
      nil -> {:error, :not_found}
      ssh_public_key -> {:ok, ssh_public_key}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  @doc """
  Creates an SSH public key.

  ## Parameters
  - `ssh_username` - The SSH username struct (validated in controller via path param)
  - `params` - Request params (validated through CreateSshPublicKeyForm)

  ## Returns
  - `{:ok, ssh_public_key}` - SSH public key created successfully
  - `{:error, changeset}` - Validation or creation failed
  """
  def create_ssh_public_key(%SshUsername{} = ssh_username, params) do
    with {:ok, attrs} <- Forms.CreateSshPublicKeyForm.changeset(params) do
      attrs = Map.put(attrs, "ssh_username_id", ssh_username.id)
      insert_ssh_public_key(attrs)
    end
  end

  # Private function for internal use (bypasses form validation when attrs already validated)
  defp insert_ssh_public_key(attrs) do
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
          time_to_live = Map.fetch!(attrs, "time_to_live")

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

                # Track in DB for cleanup (store tag and TTL for later queries)
                case %EphemeralEnrollmentKey{}
                     |> EphemeralEnrollmentKey.changeset(%{
                       token: token,
                       tag: tag,
                       time_to_live: time_to_live,
                       cluster_id: cluster.id
                     })
                     |> Repo.insert() do
                  {:ok, _} ->
                    %{token: token, key_type: "ephemeral", time_to_live: time_to_live}

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
  1. Finds expired ephemeral enrollment keys based on their individual time_to_live
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
    current_time = DateTime.utc_now()

    # Find expired tracked keys (using per-key TTL)
    # Calculate cutoff time for each key: inserted_at + time_to_live (minutes)
    expired_keys =
      from(ek in EphemeralEnrollmentKey,
        where: fragment("? + (? || ' minutes')::interval < ?", ek.inserted_at, ek.time_to_live, ^current_time),
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
    Logger.debug(
      "Processing expired key: #{enrollment_key.token} with tag: #{enrollment_key.tag}"
    )

    # Wrap entire cleanup in transaction - rollback everything if ANY step fails
    case Repo.transaction(fn ->
           # 1. Query Netmaker for nodes using this tag
           network_name = node_network_name(enrollment_key.cluster)

           netmaker_nodes =
             case Vpn.list_nodes_by_tag(enrollment_key.tag) do
               {:ok, nodes} ->
                 nodes

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
                 if Vpn.netmaker_not_found_error?(body) do
                   Logger.info("Netmaker host #{host_id} already deleted (not found)")
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
      nodes_deleted: 0,
      clusters_deleted: 0,
      aliases_cleaned: 0,
      errors: 0
    }

    result =
      Enum.reduce(clusters, result, fn cluster, acc ->
        reconcile_single_cluster(cluster, db_nodes_by_cluster[cluster.id] || [], acc)
      end)

    # Clean up orphaned clusters (exist in DB but network doesn't exist in Netmaker)
    result_with_clusters = cleanup_orphaned_clusters(clusters, result)

    result_with_clusters
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
          Logger.info(
            "Reconciliation: Added host #{host_id} to network #{network_name} (cluster: #{cluster_name})"
          )

          count + 1

        {:error, reason} ->
          Logger.warning(
            "Reconciliation: Failed to add host #{host_id} to network #{network_name}: #{inspect(reason)}"
          )

          count
      end
    end)
  end

  defp remove_extra_nodes(host_ids, network_name, cluster_name) do
    Enum.reduce(host_ids, 0, fn host_id, count ->
      case Vpn.remove_host_from_network(host_id, network_name) do
        {:ok, _} ->
          Logger.info(
            "Reconciliation: Removed host #{host_id} from network #{network_name} (cluster: #{cluster_name})"
          )

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
          Logger.info(
            "Reconciliation: Deleting orphaned node #{node.id} from DB (host not found in Netmaker)"
          )

          case Repo.delete(node) do
            {:ok, _} ->
              # Emit event for metadata recomputation
              broadcast_metadata_event({:node_deleted, node.id, node.cluster_id})

              count + 1

            {:error, changeset} ->
              Logger.error(
                "Reconciliation: Failed to delete orphaned node #{node.id}: #{inspect(changeset)}"
              )

              count
          end

        {:error, reason} ->
          Logger.warning(
            "Reconciliation: Failed to check if host #{node.netmaker_host_id} exists: #{inspect(reason)}"
          )

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
          Logger.info(
            "Reconciliation: Deleting orphaned cluster #{cluster.id} from DB (network not found in Netmaker)"
          )

          case Repo.delete(cluster) do
            {:ok, _} ->
              # Emit event for metadata recomputation
              broadcast_metadata_event({:cluster_deleted, cluster.id})

              %{result | clusters_deleted: result.clusters_deleted + 1}

            {:error, changeset} ->
              Logger.error(
                "Reconciliation: Failed to delete orphaned cluster #{cluster.id}: #{inspect(changeset)}"
              )

              %{result | errors: result.errors + 1}
          end

        {:error, reason} ->
          Logger.warning(
            "Reconciliation: Failed to check if network #{network_name} exists: #{inspect(reason)}"
          )

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
    network_name = node_network_name(alias_record.cluster)
    dns_hostname = Alias.dns_hostname(alias_record)

    # 1. Try to delete DNS entry (best-effort)
    case Nexmaker.Api.DNS.delete(network_name, dns_hostname) do
      {:ok, _} ->
        Logger.info("Deleted DNS entry for alias #{alias_record.name}: #{dns_hostname}")

      {:error, {:http_error, 500, body}} ->
        # Netmaker returns 500 for "not found" - treat as already deleted
        if Vpn.netmaker_not_found_error?(body) do
          Logger.debug(
            "DNS entry already deleted for alias #{alias_record.name}: #{dns_hostname}"
          )
        else
          Logger.warning(
            "Failed to delete DNS entry for alias #{alias_record.name}: #{inspect(body)}"
          )
        end

      {:error, reason} ->
        Logger.warning(
          "Failed to delete DNS entry for alias #{alias_record.name}: #{inspect(reason)}"
        )
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
  def get_alias(id) do
    case Repo.get(Alias, id) do
      nil -> {:error, :not_found}
      alias_record -> {:ok, Repo.preload(alias_record, :cluster)}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  @doc """
  Creates an alias for a node.

  Flow:
  1. Verify node exists and preload cluster
  2. Validate input via form
  3. Query Netmaker for node's IP address
  4. Create DNS entry in Netmaker
  5. Insert alias into DB

  If any step fails, the entire operation is rolled back.
  """
  def create_alias(%Node{} = node, params) do
    with {:ok, attrs} <- Forms.CreateAliasForm.changeset(params) do
      Repo.transaction(fn ->
        # 1. Ensure node has cluster preloaded
        node = Repo.preload(node, :cluster)

        # 2. Build attrs with node_id and cluster_id
        alias_attrs =
          Map.merge(attrs, %{
            "node_id" => node.id,
            "cluster_id" => node.cluster_id
          })

        # 3. Validate with changeset
        changeset = Alias.changeset(%Alias{}, alias_attrs)

        case Repo.insert(changeset) do
          {:ok, alias_record} ->
            # 4. Preload cluster for virtual fields
            alias_record = Repo.preload(alias_record, :cluster)

            # 5. Query Netmaker for node's IP address
            network_name = node_network_name(node.cluster)

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
      network_name = node_network_name(alias_record.cluster)
      dns_hostname = Alias.dns_hostname(alias_record)

      case Nexmaker.Api.DNS.delete(network_name, dns_hostname) do
        {:ok, _} ->
          Logger.info("Deleted DNS entry for alias #{alias_record.name}: #{dns_hostname}")

          # 3. Delete from DB
          Repo.delete!(alias_record)

        {:error, {:http_error, 500, body}} = error ->
          # Netmaker returns 500 for "not found" - treat as success for idempotency
          if Vpn.netmaker_not_found_error?(body) do
            Logger.info(
              "DNS entry already deleted for alias #{alias_record.name}: #{dns_hostname}"
            )

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

  def list_node_metrics(%Node{} = node) do
    with {:ok, raw_metrics} <- fetch_current_node_metrics(node),
         {:ok, metrics} <- build_validated_metrics(raw_metrics, node.id) do
      {:ok, metrics}
    else
      {:error, :no_vpn_ip} -> {:error, :metrics_unavailable}
      {:error, :metrics_service_not_configured} -> {:error, :metrics_unavailable}
      {:error, :metrics_service_unavailable} -> {:error, :metrics_unavailable}
      {:error, %Ecto.Changeset{}} = changeset_error -> changeset_error
      {:error, _reason} -> {:error, :metrics_unavailable}
    end
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
