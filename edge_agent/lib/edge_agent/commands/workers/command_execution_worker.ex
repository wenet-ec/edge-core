# edge_agent/lib/edge_agent/commands/workers/command_execution_worker.ex
defmodule EdgeAgent.Commands.Workers.CommandExecutionWorker do
  @moduledoc """
  Worker that processes command queue sequentially with lazy querying.

  Triggered by:
  - New command arrival (via enqueue_worker/2 in Commands context)
  - Cron scheduler every 2 minutes (safety net)

  Uses Oban's unique constraint to ensure only one worker runs at a time.
  Uses lazy querying to handle race conditions where new commands arrive during execution.
  Only focuses on execution - reporting is handled separately by CommandReportWorker.
  """

  use Oban.Worker,
    queue: :command_execution,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias EdgeAgent.Commands

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.info("CommandExecutionWorker started")

    # Process the entire queue with lazy querying
    Commands.process_command_queue()

    Logger.info("CommandExecutionWorker completed, dying")
    :ok
  end
end
