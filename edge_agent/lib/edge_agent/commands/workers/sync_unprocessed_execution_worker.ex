# edge_agent/lib/edge_agent/commands/workers/sync_unprocessed_execution_worker.ex
defmodule EdgeAgent.Commands.Workers.SyncUnprocessedExecutionWorker do
  @moduledoc """
  Worker that syncs unprocessed command executions when using HTTP fallback.

  Triggered by:
  - Cron scheduler every 2 minutes

  Only runs when:
  - VPN is down (admin_urls is empty list)
  - HTTP fallback is configured (fallback_admin_url is set)

  Fetches both "sent" and "pending" executions from admin, acknowledges pending
  executions, and stores them locally. Provides safety net for command delivery
  when VPN connectivity is unavailable.
  """

  use Oban.Worker,
    queue: :execution_syncing,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias EdgeAgent.Commands
  alias EdgeAgent.Settings

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if should_run?() do
      Logger.debug("SyncUnprocessedExecutionWorker: Starting sync")
      Commands.sync_unprocessed_command_executions()
      Logger.debug("SyncUnprocessedExecutionWorker: Completed sync")
    else
      Logger.debug("SyncUnprocessedExecutionWorker: Skipping (VPN available or fallback not configured)")
    end

    :ok
  end

  defp should_run? do
    admin_urls = Settings.get_admin_urls() || []
    fallback_url = Application.get_env(:edge_agent, :fallback_admin_url)

    admin_urls == [] and fallback_url != nil
  end
end
