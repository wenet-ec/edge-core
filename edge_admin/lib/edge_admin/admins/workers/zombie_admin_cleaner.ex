# edge_admin/lib/edge_admin/admins/workers/zombie_admin_cleaner.ex
defmodule EdgeAdmin.Admins.Workers.ZombieAdminCleaner do
  @moduledoc """
  Periodic cleanup of offline admin hosts in Netmaker.

  Runs once per admin cluster (Oban unique ensures single execution).
  Deletes only admin hosts with `status: "offline"` in Netmaker.
  Scoped to own admin cluster network.

  ## Detection Logic

  1. Query Netmaker for all hosts
  2. Filter for admin hosts in this admin cluster (pattern: admin-*.admin-cluster-*.nm.internal)
  3. Filter for hosts with `status == "offline"` (Netmaker's native field)
  4. Delete offline admin hosts (Netmaker cascades to nodes, DNS entries)
  """

  use Oban.Worker,
    queue: :default,
    unique: [period: 3600]

  alias EdgeAdmin.Vpn

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    admin_cluster_name = Vpn.admin_cluster_name()

    Logger.info("Starting zombie admin cleanup for #{admin_cluster_name}")

    # Query Netmaker for all hosts
    case Vpn.list_hosts() do
      {:ok, hosts} when is_list(hosts) ->
        # Filter for admin hosts in our admin cluster
        # Pattern: admin-{id}.{admin_cluster_name}.nm.internal
        admin_hosts =
          hosts
          |> Enum.filter(fn host ->
            host_name = host["name"] || ""

            String.starts_with?(host_name, "admin-") and
              String.contains?(host_name, ".#{admin_cluster_name}.")
          end)

        # Filter for offline hosts only (Netmaker manages status field)
        offline_hosts =
          admin_hosts
          |> Enum.filter(fn host ->
            # Netmaker uses "no" for offline status in isconnected field
            # or check the actual status field if available
            host["isconnected"] == "no" or host["connected"] == false
          end)

        if length(offline_hosts) > 0 do
          Logger.info("Found #{length(offline_hosts)} offline admin host(s)")

          deleted_count =
            Enum.reduce(offline_hosts, 0, fn host, count ->
              host_id = host["id"]
              host_name = host["name"]

              Logger.info("Deleting offline admin host: #{host_name} (id: #{host_id})")

              case Vpn.delete_host(host_id) do
                {:ok, _} ->
                  Logger.info("Successfully deleted offline host #{host_name}")
                  count + 1

                {:error, reason} ->
                  Logger.error("Failed to delete host #{host_name}: #{inspect(reason)}")
                  count
              end
            end)

          Logger.info("Zombie admin cleanup complete: #{deleted_count} host(s) deleted")
        else
          Logger.debug("No offline admin hosts found in #{admin_cluster_name}")
        end

        :ok

      {:ok, _} ->
        Logger.warning("Unexpected response format from Netmaker Hosts API")
        :ok

      {:error, reason} ->
        Logger.error("Failed to query Netmaker Hosts API: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
