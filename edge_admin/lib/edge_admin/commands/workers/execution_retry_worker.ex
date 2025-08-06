# edge_admin/lib/edge_admin/commands/workers/execution_retry_worker.ex
defmodule EdgeAdmin.Commands.Workers.ExecutionRetryWorker do
  @moduledoc """
  Cron worker that retries pending command executions in FIFO order per node.

  This worker runs periodically (every 60 seconds) to handle:
  - Failed deliveries from TargetNodesDispatchWorker
  - All executions created by TargetAllDispatchWorker
  - Any executions that become pending due to node connectivity issues

  Maintains strict FIFO ordering per node by only processing the oldest
  pending execution for each node in each run.
  """

  use Oban.Worker, queue: :command_retry, max_attempts: 1

  alias EdgeAdmin.Commands

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    # This worker doesn't need specific args since it processes all pending executions
    Commands.retry_pending_executions()
    :ok
  end
end
