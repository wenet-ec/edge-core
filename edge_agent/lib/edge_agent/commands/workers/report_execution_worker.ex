# edge_agent/lib/edge_agent/commands/workers/report_execution_worker.ex
defmodule EdgeAgent.Commands.Workers.ReportExecutionWorker do
  @moduledoc "Worker that reports completed command execution results to Admin."

  use Oban.Worker,
    queue: :report_executions,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: :incomplete
    ]

  alias EdgeAgent.Commands

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.debug("ReportExecutionWorker started")

    Commands.report_unreported_executions()

    Logger.debug("ReportExecutionWorker completed")
    :ok
  end
end
