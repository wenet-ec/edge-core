# edge_agent/lib/edge_agent/self_updates/workers/check_self_update_worker.ex
defmodule EdgeAgent.SelfUpdates.Workers.CheckSelfUpdateWorker do
  @moduledoc """
  Worker that periodically checks for self-update requests via HTTP fallback.

  This worker enables self-update functionality when VPN connectivity is unavailable
  by polling the admin API for the latest self-update request.

  ## Behavior
  - Runs every 2 hours (configured in Oban cron)
  - Only runs when: VPN down (admin_urls empty) + fallback configured + self-update enabled
  - Checks if latest self-update includes this node
  - Triggers Watchtower update if new update available
  - Tracks last check timestamp to avoid duplicate updates

  ## Guard Conditions
  The worker only executes when ALL conditions are met:
  - `admin_urls == []` - VPN discovery found no admins (VPN down)
  - `fallback_url != nil` - HTTP fallback URL configured
  - `self_update_enabled == true` - Self-update feature enabled
  """

  use Oban.Worker,
    queue: :check_self_update,
    max_attempts: 3,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :retryable]
    ]

  alias EdgeAgent.SelfUpdates
  alias EdgeAgent.Settings

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    if should_run?() do
      Logger.debug("Running self-update check (HTTP fallback mode)")
      SelfUpdates.check_self_update()
    else
      Logger.debug("Skipping self-update check (VPN mode or self-update disabled)")
      :ok
    end
  end

  # Check if worker should run
  defp should_run? do
    admin_urls = Settings.get_admin_urls()
    fallback_urls = Settings.get_admin_fallback_urls()
    self_update_enabled = Application.get_env(:edge_agent, :self_update_enabled, false)

    # Only run if: VPN down + fallback configured + self-update enabled
    admin_urls == [] and fallback_urls != [] and self_update_enabled
  end
end
