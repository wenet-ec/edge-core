# edge_agent/lib/edge_agent/metrics/workers/push_metrics_worker.ex
defmodule EdgeAgent.Metrics.Workers.PushMetricsWorker do
  @moduledoc """
  Oban worker that pushes metrics to admin when using HTTP fallback mode.

  This worker runs every 2 minutes when VPN is unavailable and fallback URL
  is configured. It scrapes local metrics exporters (host, agent, wireguard)
  and pushes them to admin for temporary caching.

  ## Conditions

  Worker only runs when:
  - VPN admin URLs are empty (no VPN connectivity)
  - Fallback admin URL is configured

  ## Schedule

  - Cron: Every 2 minutes (`"*/2 * * * *"`)
  - Queue: `:push_metrics`
  - Max attempts: 1 (best-effort, retry on next cron)
  - Unique: One job in any state at a time
  """
  use Oban.Worker,
    queue: :push_metrics,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias EdgeAgent.Metrics
  alias EdgeAgent.Settings

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    if should_run?() do
      Logger.debug("Pushing metrics to admin (HTTP fallback mode)")
      Metrics.push_metrics()
    else
      Logger.debug("Skipping metrics push (VPN available or no fallback configured)")
      :ok
    end
  end

  defp should_run? do
    admin_urls = Settings.get_admin_urls() || []
    fallback_urls = Application.get_env(:edge_agent, :admin_fallback_urls, [])

    admin_urls == [] and fallback_urls != []
  end
end
