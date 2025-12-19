# edge_admin/lib/edge_admin/vpn/workers/zombie_admin_cleaner.ex
defmodule EdgeAdmin.Vpn.Workers.ZombieAdminCleaner do
  @moduledoc """
  Periodic cleanup of stale admin hosts in the admin cluster.

  Deletes hosts whose nodes in the admin-cluster haven't checked in
  for a configured threshold (default: 120 minutes). Protects nodes that
  are in our ETS metadata to prevent self-deletion.

  ## Configuration

  - ZOMBIE_ADMIN_CLEANUP_SCHEDULE: Cron schedule (default: "*/30 * * * *" = every 30 minutes)
  - ZOMBIE_ADMIN_CHECKIN_THRESHOLD_MINUTES: Minutes since last checkin to consider dead (default: 120)
  """

  use Oban.Worker,
    queue: :zombie_admin_cleanup,
    max_attempts: 1,
    unique: [
      period: 1800,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias EdgeAdmin.Vpn

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    # Call Vpn context function - all logic lives there
    case Vpn.cleanup_zombie_admins() do
      {:ok, deleted_count} ->
        Logger.info("Zombie admin cleanup completed: #{deleted_count} host(s) deleted")
        :ok

      {:error, reason} ->
        Logger.error("Zombie admin cleanup failed: #{inspect(reason)}")
        # Return :ok anyway so job completes and next run can try again
        :ok
    end
  end
end
