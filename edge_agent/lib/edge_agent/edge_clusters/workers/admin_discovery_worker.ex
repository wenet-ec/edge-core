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
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias EdgeAgent.EdgeClusters.Discovery

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.debug("AdminDiscoveryWorker started")

    Discovery.discover_admins()

    Logger.debug("AdminDiscoveryWorker completed")
    :ok
  end
end
