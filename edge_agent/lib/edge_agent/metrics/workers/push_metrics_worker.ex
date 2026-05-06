# edge_agent/lib/edge_agent/metrics/workers/push_metrics_worker.ex
defmodule EdgeAgent.Metrics.Workers.PushMetricsWorker do
  @moduledoc """
  Oban worker that pushes metrics to admin when using HTTP fallback mode.

  When VPN is unavailable and fallback URLs are configured, scrapes local
  metrics exporters (host, agent, wireguard) and pushes them to admin for
  temporary caching.

  ## Conditions

  Worker only runs when:
  - VPN admin URLs are empty (no VPN connectivity)
  - Fallback admin URLs are configured

  ## Schedule

  - Cron: cadence configured by `PUSH_METRICS_SCHEDULE` (default: every 2
    minutes)
  - Queue: `:push_metrics`
  - Max attempts: 1 (best-effort, retry on next cron)
  - Unique: One job in `:available` or `:scheduled` state at a time
  """
  use Oban.Worker,
    queue: :push_metrics,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: [:available, :scheduled]
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
    admin_urls = Settings.get_admin_urls()
    fallback_urls = Settings.get_admin_fallback_urls()

    admin_urls == [] and fallback_urls != []
  end
end
