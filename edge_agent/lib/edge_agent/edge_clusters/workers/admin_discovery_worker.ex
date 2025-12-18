# edge_agent/lib/edge_agent/edge_clusters/workers/admin_discovery_worker.ex
defmodule EdgeAgent.EdgeClusters.Workers.AdminDiscoveryWorker do
  @moduledoc """
  Worker that discovers admins in the cluster network.

  Scans the cluster subnet to find admins and updates the admin URLs in Settings.
  Uses Oban's unique constraint to ensure only one discovery runs at a time.
  """

  use Oban.Worker,
    queue: :admin_discovery,
    max_attempts: 1,
    unique: [
      period: 300,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias EdgeAgent.EdgeClusters.Discovery

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.debug("AdminDiscoveryWorker started")

    # Always return :ok to prevent job from getting stuck in failed state
    # Discovery errors are logged but don't block the worker
    case Discovery.discover_admins() do
      {:ok, _network_name, admin_urls} ->
        Logger.debug("AdminDiscoveryWorker completed - discovered #{length(admin_urls)} admin(s)")
        :ok

      {:error, reason} ->
        Logger.warning("AdminDiscoveryWorker failed to discover admins: #{inspect(reason)}")
        # Return :ok anyway so job completes and next cron run can try again
        :ok
    end
  end
end
