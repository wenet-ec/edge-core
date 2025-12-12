# edge_agent/lib/edge_agent/commands/workers/execution_enqueue_worker.ex
defmodule EdgeAgent.Commands.Workers.ExecutionEnqueueWorker do
  @moduledoc """
  Scheduler worker that enqueues pending command executions.

  Triggered by:
  - Cron scheduler every 10 seconds
  - New command arrival

  Finds all pending executions and spawns a CommandExecutionWorker for each.
  Uses Oban's unique constraint to ensure only one enqueue worker runs at a time
  and prevent duplicate CommandExecutionWorker jobs.
  """

  use Oban.Worker,
    queue: :execution_enqueue,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias EdgeAgent.Commands

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.debug("ExecutionEnqueueWorker started")

    # Enqueue all pending executions as individual jobs
    Commands.enqueue_pending_executions()

    Logger.debug("ExecutionEnqueueWorker completed")
    :ok
  end
end
