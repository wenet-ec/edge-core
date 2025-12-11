# edge_admin/lib/edge_admin/admins/workers/zombie_admin_cleaner.ex
defmodule EdgeAdmin.Admins.Workers.ZombieAdminCleaner do
  @moduledoc """
  Periodic cleanup of offline admin hosts in Netmaker.

  Runs once per admin cluster (Oban unique ensures single execution).
  Deletes admin hosts that have offline nodes in the admin cluster.
  Scoped to own admin cluster network.

  ## Detection Logic

  1. Query Netmaker for all nodes in the admin cluster network
  2. Filter for nodes with `status == "offline"` (Netmaker's native node status field)
  3. Extract unique host IDs from offline nodes
  4. Delete offline admin hosts (Netmaker cascades to nodes, DNS entries)
  """

  use Oban.Worker,
    queue: :zombie_admin_cleanup,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias EdgeAdmin.Vpn

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    admin_cluster_name = Vpn.admin_cluster_name()

    Logger.info("Starting zombie admin cleanup for #{admin_cluster_name}")

    # Query Netmaker for all nodes in the admin cluster
    case Vpn.list_nodes(admin_cluster_name) do
      {:ok, nodes} when is_list(nodes) ->
        # Filter for offline nodes only
        offline_nodes =
          nodes
          |> Enum.filter(fn node ->
            node["status"] == "offline"
          end)

        if length(offline_nodes) > 0 do
          Logger.info("Found #{length(offline_nodes)} offline admin node(s)")

          # Get unique host IDs from offline nodes
          offline_host_ids =
            offline_nodes
            |> Enum.map(fn node -> node["hostid"] end)
            |> Enum.uniq()

          Logger.info("Found #{length(offline_host_ids)} unique offline host(s) to delete")

          deleted_count =
            Enum.reduce(offline_host_ids, 0, fn host_id, count ->
              Logger.info("Deleting offline admin host with id: #{host_id}")

              case Vpn.delete_host(host_id) do
                {:ok, _} ->
                  Logger.info("Successfully deleted offline host #{host_id}")
                  count + 1

                {:error, reason} ->
                  Logger.error("Failed to delete host #{host_id}: #{inspect(reason)}")
                  count
              end
            end)

          Logger.info("Zombie admin cleanup complete: #{deleted_count} host(s) deleted")
        else
          Logger.debug("No offline admin nodes found in #{admin_cluster_name}")
        end

        :ok

      {:ok, _} ->
        Logger.warning("Unexpected response format from Netmaker Nodes API")
        :ok

      {:error, reason} ->
        Logger.error("Failed to query Netmaker Nodes API: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
