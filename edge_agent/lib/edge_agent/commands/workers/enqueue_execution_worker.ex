# edge_agent/lib/edge_agent/commands/workers/enqueue_execution_worker.ex
defmodule EdgeAgent.Commands.Workers.EnqueueExecutionWorker do
  @moduledoc """
  Worker that enqueues recoverable command executions.
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

    Commands.enqueue_pending_executions()

    Logger.debug("EnqueueExecutionWorker completed")
    :ok
  end
end
