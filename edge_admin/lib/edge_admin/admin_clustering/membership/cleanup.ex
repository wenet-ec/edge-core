# edge_admin/lib/edge_admin/admin_clustering/membership/cleanup.ex
defmodule EdgeAdmin.AdminClustering.Membership.Cleanup do
  @moduledoc """
  Cleans up stale and orphaned Admin-cluster memberships.

  This module owns the Admin-cluster lifecycle policy. `EdgeAdmin.Vpn` remains
  the adapter for NetMaker node and host operations.
  """

  alias EdgeAdmin.AdminClustering.Metadata
  alias EdgeAdmin.Vpn

  require Logger

  @doc """
  Runs the periodic zombie Admin cleanup.

  Only the deterministic weak leader performs the cleanup, and cleanup is
  skipped while metadata is degraded.
  """
  @spec run() :: :ok
  def run do
    cond do
      Metadata.degraded?() ->
        Logger.info("Admin membership cleanup skipped — system in degraded mode")

      not Metadata.am_i_weak_leader?() ->
        Logger.debug("Admin membership cleanup skipped — not the weak leader")

      true ->
        case reap_zombies() do
          {:ok, deleted_count} ->
            Logger.info("Admin membership cleanup completed — #{deleted_count} host(s) deleted")

          {:error, reason} ->
            Logger.error("Admin membership cleanup failed — #{inspect(reason)}")
        end
    end

    :ok
  end

  @doc """
  Deletes Admin-cluster hosts whose nodes have not checked in within the
  configured threshold, except for hosts currently protected by membership
  metadata.
  """
  @spec reap_zombies() :: {:ok, non_neg_integer()} | {:error, term()}
  def reap_zombies do
    admin_cluster_name = Vpn.admin_cluster_name()
    threshold_seconds = zombie_threshold_seconds()
    protected_host_ids = protected_host_ids()

    Logger.info("Starting zombie Admin membership cleanup for #{admin_cluster_name}")
    Logger.debug("Threshold: #{threshold_seconds}s")
    Logger.debug("Protected hosts: #{inspect(protected_host_ids)}")

    case Vpn.list_nodes(admin_cluster_name) do
      {:ok, nodes} when is_list(nodes) ->
        delete_zombie_hosts(nodes, threshold_seconds, protected_host_ids, admin_cluster_name)

      {:ok, _} ->
        Logger.warning("Unexpected response format from NetMaker Nodes API")
        emit_cleanup_telemetry(0, :error)
        {:ok, 0}

      {:error, reason} ->
        Logger.error("Failed to query NetMaker Nodes API: #{inspect(reason)}")
        emit_cleanup_telemetry(0, :error)
        {:error, reason}
    end
  end

  @doc """
  Removes an orphan host created during a failed membership bootstrap.

  The full-network case is excluded because bootstrap did not attempt to
  create a host in that case.
  """
  @spec remove_orphan(String.t(), term()) :: :ok
  def remove_orphan(_admin_name, {:admin_cluster_full, _, _, _}), do: :ok

  def remove_orphan(admin_name, _reason) do
    case Vpn.get_host_id(admin_name) do
      {:ok, host_id} ->
        Logger.warning("Cleaning up orphan host #{admin_name} (#{host_id}) before exiting")

        case Vpn.delete_host(host_id) do
          {:ok, _} -> Logger.info("Deleted orphan host #{host_id}")
          {:error, reason} -> Logger.warning("Failed to delete orphan host #{host_id}: #{inspect(reason)}")
        end

      _ ->
        :ok
    end

    :ok
  end

  @doc false
  @spec zombie_node?(map(), integer(), non_neg_integer(), [String.t()] | MapSet.t()) :: boolean()
  def zombie_node?(node, current_time, threshold_seconds, protected_host_ids) do
    age_seconds = current_time - node["lastcheckin"]
    is_zombie = age_seconds > threshold_seconds
    is_protected = node["hostid"] in protected_host_ids

    if is_zombie and not is_protected do
      Logger.debug("Zombie found: node=#{node["id"]}, host=#{node["hostid"]} (age: #{age_seconds}s)")
      true
    else
      false
    end
  end

  defp zombie_threshold_seconds do
    Application.get_env(:edge_admin, :zombie_admin_checkin_threshold_minutes, 120) * 60
  end

  defp delete_zombie_hosts(nodes, threshold_seconds, protected_host_ids, cluster_name) do
    current_time = System.system_time(:second)

    zombie_host_ids =
      nodes
      |> Enum.filter(&zombie_node?(&1, current_time, threshold_seconds, protected_host_ids))
      |> Enum.map(& &1["hostid"])
      |> Enum.uniq()

    if zombie_host_ids == [] do
      Logger.debug("No zombie Admin memberships found in #{cluster_name}")
      emit_cleanup_telemetry(0, :success)
      {:ok, 0}
    else
      Logger.info("Found #{length(zombie_host_ids)} unique zombie host(s) to delete")
      deleted_count = Enum.reduce(zombie_host_ids, 0, &delete_zombie_host/2)
      emit_cleanup_telemetry(deleted_count, :success)
      {:ok, deleted_count}
    end
  end

  defp delete_zombie_host(host_id, count) do
    Logger.info("Deleting zombie Admin host: #{host_id}")

    case Vpn.delete_host(host_id) do
      {:ok, _} ->
        Logger.info("Successfully deleted zombie host #{host_id}")
        count + 1

      {:error, reason} ->
        Logger.error("Failed to delete host #{host_id}: #{inspect(reason)}")
        count
    end
  end

  defp protected_host_ids do
    Metadata.get_admin_cluster()
    |> Map.get(:topology, [])
    |> Enum.map(&Map.get(&1, :vpn_host_id))
    |> Enum.reject(&is_nil/1)
  rescue
    _ ->
      Logger.warning("Failed to get Admin-cluster metadata")
      []
  end

  defp emit_cleanup_telemetry(deleted_count, result) do
    :telemetry.execute(
      [:edge_admin, :vpn, :zombie_admin_cleanup],
      %{deleted_count: deleted_count},
      %{result: result}
    )
  end
end
