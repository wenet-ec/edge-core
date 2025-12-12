# edge_agent/lib/edge_agent/commands/workers/execution_report_worker.ex
defmodule EdgeAgent.Commands.Workers.ExecutionReportWorker do
  @moduledoc """
  Worker that reports completed command execution results to admin.

  Triggered by:
  - After command execution completes (via enqueue_worker/2 in Commands context)
  - Cron scheduler every 30 seconds (safety net for timely reporting)

  Uses Oban's unique constraint to ensure only one worker runs at a time.

  - Orders by inserted_at (oldest first) to maintain execution sequence
  - Stops on first network error - lets next cron run retry
  - No complex retry logic - relies on frequent scheduling for reliability

  Runs frequently to ensure timely reporting and fast recovery from
  network partitions or temporary admin unavailability.
  """

  use Oban.Worker,
    queue: :execution_report,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias EdgeAgent.Commands

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.debug("ExecutionReportWorker started")

    # Report unreported executions in order
    Commands.report_unreported_executions()

    Logger.debug("ExecutionReportWorker completed")
    :ok
  end
end
