# edge_agent/lib/edge_agent/commands/workers/enqueue_execution_worker.ex
defmodule EdgeAgent.Commands.Workers.EnqueueExecutionWorker do
  @moduledoc """
  Scheduler worker that enqueues pending command executions.

  Triggered by:
  - Cron scheduler at the cadence configured by `ENQUEUE_EXECUTIONS_SCHEDULE`
    (default: every minute)
  - New command arrival

  Finds all pending executions and spawns a ExecuteCommandWorker for each.
  Uses Oban's unique constraint to ensure only one enqueue worker runs at a time
  and prevent duplicate ExecuteCommandWorker jobs.
  """

  use Oban.Worker,
    queue: :enqueue_executions,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: :incomplete
    ]

  alias EdgeAgent.Commands

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.debug("EnqueueExecutionWorker started")

    # Enqueue all pending executions as individual jobs
    Commands.enqueue_pending_executions()

    Logger.debug("EnqueueExecutionWorker completed")
    :ok
  end
end
