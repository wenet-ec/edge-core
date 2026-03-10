# edge_agent/lib/edge_agent/edge_clusters/workers/report_health_check_worker.ex
defmodule EdgeAgent.EdgeClusters.Workers.ReportHealthCheckWorker do
  @moduledoc """
  Worker that reports node health to admin when using HTTP fallback.

  Triggered by:
  - Cron scheduler every 2 minutes

  Only runs when:
  - VPN is down (admin_urls is empty list)
  - HTTP fallback is configured (admin_fallback_urls stored in Settings)

  Reports node health status (healthy/unhealthy) to admin, allowing admin
  to track node health when direct VPN pinging is unavailable.
  """

  use Oban.Worker,
    queue: :report_health_check,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: [:available, :scheduled]
    ]

  alias EdgeAgent.EdgeClusters.HealthCheck
  alias EdgeAgent.Settings

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if should_run?() do
      Logger.debug("ReportHealthCheckWorker: Starting health check report")
      HealthCheck.report()
      Logger.debug("ReportHealthCheckWorker: Completed health check report")
    else
      Logger.debug("ReportHealthCheckWorker: Skipping (VPN available or fallback not configured)")
    end

    :ok
  end

  defp should_run? do
    admin_urls = Settings.get_admin_urls()
    fallback_urls = Settings.get_admin_fallback_urls()

    admin_urls == [] and fallback_urls != []
  end
end
