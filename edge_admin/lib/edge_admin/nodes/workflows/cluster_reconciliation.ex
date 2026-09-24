# edge_admin/lib/edge_admin/nodes/workflows/cluster_reconciliation.ex
defmodule EdgeAdmin.Nodes.Workflows.ClusterReconciliation do
  @moduledoc """
  Reconciles the Admin database with Edge VPN cluster and node state.

  The database remains the source of truth. Reconciliation repairs missing
  Edge VPN networks and memberships, removes unmanaged drift, and delegates
  alias DNS repair to `EdgeAdmin.Nodes.Resources.AliasResources`.
  """

  import Ecto.Query, warn: false

  alias EdgeAdmin.AdminClustering.Metadata
  alias EdgeAdmin.Commands
  alias EdgeAdmin.Nodes.Queries.ClusterQueries
  alias EdgeAdmin.Nodes.Resources.AliasResources
  alias EdgeAdmin.Nodes.Resources.ClusterResources
  alias EdgeAdmin.Nodes.Schemas.Cluster
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Nodes.Workers.DeleteClusterWorker
  alias EdgeAdmin.Nodes.Workers.ReconcileClusterWorker
  alias EdgeAdmin.Repo
  alias EdgeAdmin.Vpn

  require Logger

  defp cluster_active?(cluster_id) do
    Repo.exists?(ClusterQueries.active_by_id(cluster_id))
  end

  @doc """
  Reconciles one active cluster with the VPN control plane.
  """
  @spec reconcile_cluster(String.t()) :: {:ok, map()} | {:error, :not_found}
  def reconcile_cluster(cluster_name) do
    case ClusterResources.get(cluster_name) do
      {:ok, cluster} -> {:ok, reconcile_active_cluster(cluster)}
      {:error, :not_found} = error -> error
    end
  end

  @doc """
  Enqueues active-cluster reconciliation and retired-cluster deletion work, then cleans
  up Edge VPN cluster networks that no database row owns.
  """
  @spec enqueue_cluster_reconciliation() :: :ok | {:error, term()}
  def enqueue_cluster_reconciliation do
    enqueue_cluster_reconciliation_page(1, 0)
    cleanup_ghost_cluster_networks()
  end

  defp empty_reconcile_stats do
    %{
      nodes_added: 0,
      nodes_removed: 0,
      nodes_deleted: 0,
      aliases_cleaned: 0,
      aliases_repaired: 0,
      ghost_aliases_cleaned: 0,
      errors: 0
    }
  end

  defp reconcile_active_cluster(%Cluster{} = cluster) do
    acc = empty_reconcile_stats()

    db_nodes = Repo.all(from(n in Node, where: n.cluster_id == ^cluster.id, preload: [:cluster]))

    result = reconcile_single_cluster(cluster, db_nodes, acc)
    AliasResources.cleanup_ghost_aliases([cluster], result)
  end

  defp enqueue_cluster_reconciliation_page(page, total) do
    {:ok, {clusters, meta}} =
      ClusterResources.list_for_reconciliation(%{"page_size" => "500", "page" => to_string(page)})

    count =
      Enum.reduce(clusters, 0, fn cluster, acc ->
        worker =
          if is_nil(cluster.deleted_at) do
            ReconcileClusterWorker.new(%{"cluster_name" => cluster.name})
          else
            DeleteClusterWorker.new(%{
              "cluster_name" => cluster.name,
              "cluster_id" => cluster.id
            })
          end

        case Oban.insert(worker) do
          {:ok, _job} ->
            acc + 1

          {:error, reason} ->
            Logger.warning("Failed to enqueue reconciliation for cluster #{cluster.name}: #{inspect(reason)}")

            acc
        end
      end)

    if meta.has_next_page? do
      enqueue_cluster_reconciliation_page(page + 1, total + count)
    else
      Logger.info("Enqueued #{total + count} cluster maintenance jobs")
      :ok
    end
  end

  defp reconcile_single_cluster(cluster, db_nodes, acc) do
    network_name = Cluster.network_name(cluster)

    Logger.debug("Reconciling cluster #{cluster.name} (network: #{network_name})")

    with true <- cluster_active?(cluster.id),
         :ok <- ensure_cluster_network(cluster) do
      expected_host_ids = MapSet.new(db_nodes, & &1.vpn_host_id)

      case Vpn.list_nodes(network_name) do
        {:ok, vpn_nodes} ->
          if cluster_active?(cluster.id) do
            actual_host_ids = vpn_host_ids(vpn_nodes)

            counts = reconcile_cluster_nodes(cluster, db_nodes, vpn_nodes, expected_host_ids, actual_host_ids)

            merge_cluster_reconcile_counts(acc, counts)
          else
            acc
          end

        {:error, reason} ->
          Logger.error("Failed to list nodes for cluster #{cluster.name}: #{inspect(reason)}")
          %{acc | errors: acc.errors + 1}
      end
    else
      false ->
        acc

      :retired ->
        acc

      {:error, reason} ->
        Logger.error("Failed to ensure network for cluster #{cluster.name}: #{inspect(reason)}")
        %{acc | errors: acc.errors + 1}
    end
  end

  defp reconcile_cluster_nodes(cluster, db_nodes, vpn_nodes, expected_host_ids, actual_host_ids) do
    network_name = Cluster.network_name(cluster)
    expected_hostnames = MapSet.new(db_nodes, &Node.node_name/1)

    orphaned_nodes = orphaned_db_nodes(db_nodes, expected_host_ids, actual_host_ids)

    aliases_cleaned = AliasResources.cleanup_orphaned_aliases(orphaned_nodes)
    {deleted, unenrolled_host_ids} = delete_orphaned_nodes(orphaned_nodes)
    added = add_missing_nodes(unenrolled_host_ids, network_name, cluster.name)

    {managed_extra, unmanaged_extra} = partition_extra_vpn_hosts(actual_host_ids, expected_host_ids)

    removed = remove_extra_nodes(managed_extra, network_name, cluster.name)

    {orphan_swept, evicted, errors} =
      reconcile_host_inventory(
        vpn_nodes,
        unmanaged_extra,
        expected_hostnames,
        network_name,
        cluster.name
      )

    %{
      added: added,
      removed: removed + evicted,
      deleted: deleted + orphan_swept,
      aliases_cleaned: aliases_cleaned,
      errors: errors
    }
  end

  defp merge_cluster_reconcile_counts(acc, counts) do
    %{
      nodes_added: acc.nodes_added + counts.added,
      nodes_removed: acc.nodes_removed + counts.removed,
      nodes_deleted: acc.nodes_deleted + counts.deleted,
      aliases_cleaned: acc.aliases_cleaned + counts.aliases_cleaned,
      aliases_repaired: acc.aliases_repaired,
      ghost_aliases_cleaned: acc.ghost_aliases_cleaned,
      errors: acc.errors + counts.errors
    }
  end

  defp vpn_host_ids(vpn_nodes) do
    vpn_nodes
    |> Enum.map(& &1["hostid"])
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  # The global inventory answers the only question these destructive branches need:
  # whether a node's host still exists at all. Do not filter it through another node
  # snapshot, which can disagree with the node list this reconciliation is processing.
  defp host_hostname_map do
    with {:ok, hosts} <- Vpn.list_hosts() do
      {:ok, Map.new(hosts, fn host -> {host["id"], host["name"] || ""} end)}
    end
  end

  defp reconcile_host_inventory(vpn_nodes, unmanaged_extra, expected_hostnames, network_name, cluster_name) do
    case host_hostname_map() do
      {:ok, hostnames_by_id} ->
        live_host_ids = hostnames_by_id |> Map.keys() |> MapSet.new()

        orphan_swept = sweep_orphan_nodes_in_network(vpn_nodes, live_host_ids, network_name)

        evicted =
          maybe_evict_rogue_hosts(
            unmanaged_extra,
            hostnames_by_id,
            expected_hostnames,
            network_name,
            cluster_name
          )

        {orphan_swept, evicted, 0}

      {:error, reason} ->
        Logger.warning(
          "Reconciliation: Failed to list Edge VPN hosts for #{network_name}; " <>
            "skipping orphan-node sweep and rogue-host eviction: #{inspect(reason)}"
        )

        {0, 0, 1}
    end
  end

  defp orphaned_db_nodes(db_nodes, expected_host_ids, actual_host_ids) do
    orphaned_host_ids = MapSet.difference(expected_host_ids, actual_host_ids)
    Enum.filter(db_nodes, fn node -> node.vpn_host_id in orphaned_host_ids end)
  end

  defp partition_extra_vpn_hosts(actual_host_ids, expected_host_ids) do
    extra_in_vpn = MapSet.difference(actual_host_ids, expected_host_ids)

    all_db_host_ids =
      from(n in Node, select: n.vpn_host_id)
      |> Repo.all()
      |> MapSet.new()

    {
      MapSet.intersection(extra_in_vpn, all_db_host_ids),
      MapSet.difference(extra_in_vpn, all_db_host_ids)
    }
  end

  defp maybe_evict_rogue_hosts(host_ids, host_hostname_map, expected_hostnames, network_name, cluster_name) do
    if Application.get_env(:edge_admin, :evict_rogue_hosts, true) do
      evict_rogue_hosts(host_ids, host_hostname_map, expected_hostnames, network_name, cluster_name)
    else
      if not MapSet.equal?(host_ids, MapSet.new()) do
        Logger.info(
          "Reconciliation: #{MapSet.size(host_ids)} unrecognized host(s) in #{network_name} — eviction disabled (EVICT_ROGUE_HOSTS=false)"
        )
      end

      0
    end
  end

  # Heals the upstream Edge VPN bug (`RemoveHost` iterating the cached
  # `host.Nodes` slice): a node row can survive a host delete and remain
  # visible to peer pulls as a dead allowed-ip. Detection: `node["hostid"]`
  # references a host that no longer exists in the global host inventory. Cleanup
  # force-deletes by `(network, node_id)`, which routes through
  # `DeleteNode(purge=true)` and skips the broken read path.
  #
  # The synchronous sweep in `delete_node/1` covers the originating case;
  # this is the backstop for orphans created before that fix shipped or by
  # paths outside `delete_node/1` (e.g. UI deletes hitting Edge VPN directly).
  defp sweep_orphan_nodes_in_network(vpn_nodes, live_host_ids, network_name) do
    vpn_nodes
    |> Enum.filter(fn nm_node ->
      host_id = nm_node["hostid"]
      is_binary(host_id) and not MapSet.member?(live_host_ids, host_id)
    end)
    |> Enum.reduce(0, fn nm_node, count ->
      node_id = nm_node["id"]
      host_id = nm_node["hostid"]

      case Vpn.delete_node(network_name, node_id) do
        {:ok, _} ->
          Logger.warning(
            "Reconciliation: swept orphan node #{node_id} (dangling hostid #{host_id}) from #{network_name}"
          )

          count + 1

        {:error, :not_found} ->
          count

        {:error, reason} ->
          Logger.error(
            "Reconciliation: failed to sweep orphan node #{node_id} from #{network_name}: #{inspect(reason)}"
          )

          count
      end
    end)
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

  defp evict_rogue_hosts(host_ids, host_hostname_map, expected_hostnames, network_name, cluster_name) do
    Enum.reduce(host_ids, 0, fn host_id, count ->
      hostname = Map.get(host_hostname_map, host_id, "")

      cond do
        String.starts_with?(hostname, "admin-") ->
          # Admin nodes are handled by the zombie admin cleaner - never touch them
          Logger.debug(
            "Reconciliation: Skipping admin host #{host_id} (#{hostname}) in network #{network_name} - handled by zombie cleaner"
          )

          count

        MapSet.member?(expected_hostnames, hostname) ->
          Logger.warning(
            "Reconciliation: Skipping rogue eviction for host #{host_id} (#{hostname}) in #{network_name} because hostname matches an existing node identity"
          )

          count

        true ->
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
  # of host ID strings confirmed to exist in Edge VPN but not enrolled in this network.
  # These are passed to add_missing_nodes to re-enroll them.
  # Host IDs deleted from DB (host gone from Edge VPN entirely) are excluded
  # so add_missing_nodes never calls add_host_to_network on non-existent hosts.
  defp delete_orphaned_nodes(orphaned_nodes) do
    Enum.reduce(orphaned_nodes, {0, MapSet.new()}, fn node, {count, unenrolled_ids} ->
      # Check if host exists in Edge VPN at all
      case Vpn.get_host(node.vpn_host_id) do
        {:ok, _host} ->
          # Host exists in Edge VPN but is not enrolled in this network.
          # Don't delete from DB - add_missing_nodes will re-enroll it.
          Logger.debug(
            "Reconciliation: Host #{node.vpn_host_id} exists in Edge VPN but is not enrolled in this network, skipping DB deletion"
          )

          {count, MapSet.put(unenrolled_ids, node.vpn_host_id)}

        {:error, :not_found} ->
          # Host doesn't exist in Edge VPN at all - safe to delete from DB.
          # This means deletion was attempted and Edge VPN succeeded but DB failed.
          Logger.info("Reconciliation: Deleting orphaned node #{node.id} from DB (host not found in Edge VPN)")

          case delete_node_from_db(node) do
            {:ok, _} ->
              {count + 1, unenrolled_ids}

            {:error, changeset} ->
              Logger.error("Reconciliation: Failed to delete orphaned node #{node.id}: #{inspect(changeset)}")
              {count, unenrolled_ids}
          end

        {:error, reason} ->
          Logger.warning("Reconciliation: Failed to check if host #{node.vpn_host_id} exists: #{inspect(reason)}")
          {count, unenrolled_ids}
      end
    end)
  end

  defp ensure_cluster_network(cluster) do
    case cluster_network_state(cluster) do
      :present -> :ok
      :missing -> create_missing_cluster_network(cluster)
      {:error, _reason} = error -> error
    end
  end

  defp cluster_network_state(cluster) do
    network_name = Cluster.network_name(cluster)

    case Vpn.get_network(network_name) do
      {:ok, %{"addressrange" => ipv4_range, "addressrange6" => ipv6_range}}
      when ipv4_range == cluster.ipv4_range and ipv6_range == cluster.ipv6_range ->
        :present

      {:ok, _network} ->
        {:error, :immutable_range_mismatch}

      {:error, :not_found} ->
        :missing

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_missing_cluster_network(cluster) do
    if cluster_active?(cluster.id) do
      network_name = Cluster.network_name(cluster)

      opts = %{addressrange: cluster.ipv4_range, addressrange6: cluster.ipv6_range}

      case Vpn.create_network(network_name, opts) do
        {:ok, _} ->
          Logger.info("Reconciliation: Recreated missing Edge VPN network #{network_name}")
          :ok

        {:error, :already_exists} ->
          case cluster_network_state(cluster) do
            :present -> :ok
            :missing -> {:error, :network_not_found_after_create}
            {:error, _reason} = error -> error
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      :retired
    end
  end

  # Deletes Edge VPN `cluster-*` networks that have no matching database row. Retired
  # rows count as owned until DeleteClusterWorker confirms their network is gone, so
  # this sweep cannot race a cluster retirement.
  defp cleanup_ghost_cluster_networks do
    case delete_ghost_cluster_networks() do
      {:ok, _deleted} ->
        :ok

      {:error, _reason} = error ->
        error
    end
  end

  defp delete_ghost_cluster_networks do
    with {:ok, vpn_networks} <- Vpn.list_networks() do
      vpn_cluster_names =
        vpn_networks
        |> Enum.map(& &1["netid"])
        |> Enum.filter(&String.starts_with?(&1, "cluster-"))
        |> MapSet.new()

      # Retired rows stay in this set until their network deletion is confirmed, so
      # the ghost sweep cannot race a retirement and delete its network incorrectly.
      db_network_names =
        from(c in Cluster, select: c.name)
        |> Repo.all()
        |> MapSet.new(&Cluster.network_name/1)

      deleted =
        vpn_cluster_names
        |> MapSet.difference(db_network_names)
        |> Enum.count(&delete_ghost_network/1)

      {:ok, deleted}
    end
  end

  defp delete_ghost_network(network_name) do
    if cluster_exists_for_network?(network_name) do
      false
    else
      case Vpn.delete_network(network_name) do
        {:ok, _} ->
          Logger.info("Reconciliation: Deleted ghost Edge VPN network #{network_name} (no matching DB cluster)")
          true

        {:error, :not_found} ->
          false

        {:error, reason} ->
          Logger.warning("Reconciliation: Failed to delete ghost network #{network_name}: #{inspect(reason)}")
          false
      end
    end
  end

  defp cluster_exists_for_network?(network_name) do
    cluster_name = String.replace_prefix(network_name, "cluster-", "")

    Repo.exists?(from(c in Cluster, where: c.name == ^cluster_name))
  end

  defp delete_node_from_db(%Node{} = node) do
    node = Repo.preload(node, :cluster)

    case Repo.transaction(fn ->
           dropped_executions = Commands.drop_node_command_executions(node.id, node.cluster.name)

           case Repo.delete(node) do
             {:ok, deleted_node} -> {deleted_node, dropped_executions}
             {:error, changeset} -> Repo.rollback(changeset)
           end
         end) do
      {:ok, {deleted_node, dropped_executions}} ->
        Commands.publish_dropped_command_executions(dropped_executions)
        Metadata.Events.publish(:node_deleted)
        {:ok, deleted_node}

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
