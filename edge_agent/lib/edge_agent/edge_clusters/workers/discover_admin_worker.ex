# edge_agent/lib/edge_agent/edge_clusters/workers/discover_admin_worker.ex
defmodule EdgeAgent.EdgeClusters.Workers.DiscoverAdminWorker do
  @moduledoc """
  Worker that discovers admins in the cluster network.

  Scans the cluster subnet to find admins and updates the admin URLs in Settings.
  Uses Oban's unique constraint to ensure only one discovery runs at a time.
  """

  use Oban.Worker,
    queue: :discover_admins,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias EdgeAgent.EdgeClusters.Discovery

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.debug("DiscoverAdminWorker started")

    # Discovery always succeeds - returns empty list if no admins found
    {:ok, _network_name, admin_urls} = Discovery.discover_admins()

    Logger.debug("DiscoverAdminWorker completed - discovered #{length(admin_urls)} admin(s)")

    :telemetry.execute(
      [:edge_agent, :discovery, :scan],
      %{admins_found: length(admin_urls), count: 1, total: 1},
      %{status: if(length(admin_urls) > 0, do: :success, else: :empty)}
    )

    :ok
  end
end
