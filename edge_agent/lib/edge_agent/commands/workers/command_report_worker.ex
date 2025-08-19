# edge_agent/lib/edge_agent/commands/workers/command_report_worker.ex
defmodule EdgeAgent.Commands.Workers.CommandReportWorker do
  @moduledoc """
  Periodic worker that reports completed command execution results.

  - Orders by inserted_at (oldest first) to maintain execution sequence
  - Stops on first network error - lets next cron run retry
  - No complex retry logic - relies on frequent scheduling for reliability

  Runs more frequently than before to ensure timely reporting and fast
  recovery from network partitions or temporary admin unavailability.
  """

  use Oban.Worker, queue: :command_reporting, max_attempts: 1

  alias EdgeAgent.Commands

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.debug("CommandReportWorker started")

    # Report unreported executions in order
    Commands.report_unreported_executions()

    Logger.debug("CommandReportWorker completed")
    :ok
  end
end
