# edge_admin/lib/edge_admin/nodes.ex
defmodule EdgeAdmin.Nodes do
  @moduledoc """
  The Nodes context.
  """

  import Ecto.Query, warn: false

  alias EdgeAdmin.FilteringPagination
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
  Gets a single cluster by ID.
  Raises `Ecto.NoResultsError` if the Cluster does not exist.
  """
  def get_cluster!(id) do
    from(c in Cluster,
      left_join: n in assoc(c, :nodes),
      where: c.id == ^id,
      group_by: c.id,
      select_merge: %{node_count: count(n.id)}
    )
    |> Repo.one!()
  end

  @doc """
  Gets a single cluster by name.
  Returns `nil` if the Cluster does not exist.
  """
  def get_cluster_by_name(name) do
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
      network_name = Vpn.cluster_network_name(cluster.name)

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
      network_name = Vpn.cluster_network_name(cluster.name)

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

  def get_node!(id) do
    Node
    |> Repo.get!(id)
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

  Performs cluster migration via Netmaker:
  1. Verifies host is online (uses Netmaker's status field)
  2. Adds host to new network
  3. Deletes node from old network
  4. Updates DB
  5. Emits event for metadata recomputation
  """
  def change_node_cluster(%Node{} = node, new_cluster_id) do
    Repo.transaction(fn ->
      old_cluster = get_cluster!(node.cluster_id)
      new_cluster = get_cluster!(new_cluster_id)

      # 1. Verify host online (use Netmaker's node status)
      old_network_name = Vpn.cluster_network_name(old_cluster.name)

      case Vpn.get_node(old_network_name, node.id) do
        {:ok, netmaker_node} ->
          # Use Netmaker's computed status field instead of manual lastcheckin comparison
          # Status is computed by Netmaker based on lastcheckin, connected state, and static node config
          if netmaker_node["status"] != "online" do
            Repo.rollback(:host_offline)
          end

        {:error, reason} ->
          Repo.rollback(reason)
      end

      # 2. Add host to new network
      new_network_name = Vpn.cluster_network_name(new_cluster.name)

      case Vpn.add_host_to_network(node.netmaker_host_id, new_network_name) do
        {:ok, _} ->
          # 3. Delete node from old network
          case Vpn.delete_node(old_network_name, node.id) do
            {:ok, _} ->
              # 4. Update database
              updated_node =
                node
                |> Ecto.Changeset.change(cluster_id: new_cluster_id)
                |> Repo.update!()

              # 5. Emit PubSub event for metadata recomputation (cluster migration)
              Phoenix.PubSub.broadcast(
                EdgeAdmin.PubSub,
                "#{Vpn.admin_cluster_name()}:metadata",
                {:node_updated, node.id, node.cluster_id, new_cluster_id}
              )

              updated_node

            {:error, reason} ->
              Repo.rollback(reason)
          end

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
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
      # 1. Delete from Netmaker first (critical - must succeed)
      cluster = get_cluster!(node.cluster_id)
      network_name = Vpn.cluster_network_name(cluster.name)

      case Vpn.delete_node(network_name, node.id) do
        {:ok, _} ->
          Logger.info("Deleted Netmaker node #{node.id} from network #{network_name}")

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
          Logger.error("Failed to delete Netmaker node #{node.id}: #{inspect(reason)}")
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
  def register_agent_node(attrs) do
    %{
      "node_id" => node_id,
      "cluster_id" => cluster_id
    } = attrs

    # 1. Verify cluster exists
    cluster = get_cluster!(cluster_id)

    # 2. Verify node exists in Netmaker
    network_name = Vpn.cluster_network_name(cluster.name)

    case Vpn.get_node(network_name, node_id) do
      {:ok, netmaker_node} ->
        netmaker_host_id = netmaker_node["hostid"]

        # 3. Generate new tokens on every registration
        existing_node = Repo.get(Node, node_id)
        is_new_node = is_nil(existing_node)

        api_token = generate_token()
        proxy_password = generate_token()

        now = DateTime.utc_now() |> DateTime.truncate(:second)

        # 4. Create or update node record
        node_attrs = %{
          id: node_id,
          cluster_id: cluster_id,
          netmaker_host_id: netmaker_host_id,
          id_type: attrs["id_type"],
          status: "online",
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
                {:node_created, node_id, cluster_id}
              )
            end

            {:ok, node, api_token, proxy_password}

          {:error, changeset} ->
            {:error, changeset}
        end

      {:error, :not_found} ->
        {:error, :node_not_found_in_netmaker}
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
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
    page_result =
      FilteringPagination.paginate(
        Node,
        params,
        filterable_fields: [:status, :id_type, :cluster_id],
        sortable_fields: [:inserted_at, :updated_at, :status, :last_seen_at],
        default_sort: "inserted_at:desc",
        repo: Repo
      )

    page_result
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
      {public_keys_attrs, username_attrs} = Map.pop(attrs, :public_keys, [])

      # Create username
      case create_ssh_username(username_attrs) do
        {:ok, username} ->
          # Create public keys if provided
          keys =
            Enum.map(public_keys_attrs, fn key_attrs ->
              key_attrs = Map.put(key_attrs, :ssh_username_id, username.id)

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
  Creates an enrollment key for a cluster.

  ## Parameters
    - cluster_id: The cluster ID to create the key for
    - attrs: Map with:
      - :key_type - "ephemeral" (tracked in DB, auto-cleanup) or "permanent" (not tracked), default "permanent"
      - :expiry - Seconds until expiration, default 86400 (24 hours)
      - :uses - Number of uses, default 1

  ## Returns
    - {:ok, %{key_value: string, key_type: string, tracked: boolean}} on success
    - {:error, changeset | reason} on failure

  ## Examples
      # Permanent key (production edge nodes, not tracked)
      create_enrollment_key(cluster_id, %{key_type: "permanent", expiry: 604800})
      # => {:ok, %{key_value: "nmkey-...", key_type: "permanent", tracked: false}}

      # Ephemeral key (staff/testing, tracked for cleanup)
      create_enrollment_key(cluster_id, %{key_type: "ephemeral", expiry: 86400})
      # => {:ok, %{key_value: "nmkey-...", key_type: "ephemeral", tracked: true}}
  """
  def create_enrollment_key(cluster_id, attrs \\ %{}) do
    # Parse parameters
    key_type = Map.get(attrs, :key_type, Map.get(attrs, "key_type", "permanent"))
    expiry = Map.get(attrs, :expiry, Map.get(attrs, "expiry", 86400))
    uses = Map.get(attrs, :uses, Map.get(attrs, "uses", 1))

    # Validate key_type
    if key_type not in ["ephemeral", "permanent"] do
      {:error, "key_type must be 'ephemeral' or 'permanent'"}
    else
      Repo.transaction(fn ->
        # 1. Get cluster
        cluster = get_cluster!(cluster_id)
        network_name = Vpn.cluster_network_name(cluster.name)

        # 2. Generate unique tag for this key (Netmaker requires unique tags per network)
        # Format: {key_type}-{timestamp}-{random}
        timestamp = System.system_time(:millisecond)
        random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
        tag = "#{key_type}-#{timestamp}-#{random}"

        # 3. Create enrollment key in Netmaker
        case Vpn.create_enrollment_key(network_name, %{
               expiration: expiry,
               uses_remaining: uses,
               tags: [tag]
             }) do
          {:ok, netmaker_key} ->
            key_value = netmaker_key["value"]

            # 4. Only track ephemeral keys in DB
            if key_type == "ephemeral" do
              case %EphemeralEnrollmentKey{}
                   |> EphemeralEnrollmentKey.changeset(%{
                     key_value: key_value,
                     cluster_id: cluster_id
                   })
                   |> Repo.insert() do
                {:ok, _} ->
                  %{key_value: key_value, key_type: key_type, tracked: true}

                {:error, changeset} ->
                  Repo.rollback(changeset)
              end
            else
              # Permanent key - don't track in DB
              %{key_value: key_value, key_type: key_type, tracked: false}
            end

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)
    end
  end

  @doc """
  Gets hosts enrolled with a specific enrollment key from Netmaker.

  Returns list of Netmaker host records.
  """
  def get_hosts_by_enrollment_key(cluster_id, key_value) do
    cluster = get_cluster!(cluster_id)
    network_name = Vpn.cluster_network_name(cluster.name)

    case Vpn.list_hosts(network_name) do
      {:ok, hosts} ->
        # Filter hosts that were enrolled with this key
        # Netmaker stores the enrollment key ID in host metadata
        hosts
        |> Enum.filter(fn host ->
          # Check if host has the enrollment key in metadata
          Map.get(host, "enrollmentkey") == key_value
        end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Deletes a host from Netmaker.

  This also deletes all nodes associated with the host.
  """
  def delete_host(cluster_id, host_id) do
    cluster = get_cluster!(cluster_id)
    network_name = Vpn.cluster_network_name(cluster.name)

    Vpn.delete_host(network_name, host_id)
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
    Logger.debug("Processing expired key: #{enrollment_key.key_value}")

    # Wrap entire cleanup in transaction - rollback everything if ANY step fails
    case Repo.transaction(fn ->
           # 1. Query Netmaker for hosts using this key
           netmaker_hosts =
             get_hosts_by_enrollment_key(enrollment_key.cluster_id, enrollment_key.key_value)

           host_ids = Enum.map(netmaker_hosts, & &1["id"])

           Logger.debug("Found #{length(host_ids)} hosts enrolled with this key")

           # 2. Delete each Netmaker host (fail entire transaction if ANY deletion fails)
           Enum.each(netmaker_hosts, fn host ->
             case delete_host(enrollment_key.cluster_id, host["id"]) do
               {:ok, _} ->
                 Logger.info(
                   "Deleted Netmaker host #{host["id"]} from cluster #{enrollment_key.cluster_id}"
                 )

               {:error, reason} ->
                 Logger.error("Failed to delete host #{host["id"]}: #{inspect(reason)}")
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
           case Vpn.delete_enrollment_key(enrollment_key.key_value) do
             {:ok, _} ->
               Logger.info("Deleted enrollment key from Netmaker: #{enrollment_key.key_value}")

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
             deleted_hosts: length(netmaker_hosts),
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
          "Transaction failed for ephemeral key #{enrollment_key.key_value}: #{inspect(reason)}"
        )

        acc
    end
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
      dns_name = Node.dns_hostname(node)
      instance = "#{dns_name}:#{node.metrics_port}"

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
