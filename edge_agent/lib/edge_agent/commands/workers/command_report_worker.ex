# edge_agent/lib/edge_agent/commands/workers/command_report_worker.ex
defmodule EdgeAgent.Commands.Workers.CommandReportWorker do
  @moduledoc """
  Periodic worker that reports unreported command execution results.

  Runs on schedule to catch any failed reports from CommandExecutionWorker
  or handle network partition scenarios.
  """

  use Oban.Worker, queue: :command_reporting, max_attempts: 1

  alias EdgeAgent.Commands
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.debug("CommandReportWorker started")

    # Report any unreported executions
    Commands.report_unreported_executions()

    Logger.debug("CommandReportWorker completed")
    :ok
  end
end
