# edge_agent/lib/edge_agent/commands/workers/command_execution_worker.ex
defmodule EdgeAgent.Commands.Workers.CommandExecutionWorker do
  @moduledoc """
  Event-triggered worker that processes the entire command queue sequentially.

  Spawned when new commands arrive and no worker exists.
  Processes all pending commands in FIFO order, attempts batch reporting,
  then dies when queue is empty.
  """

  use Oban.Worker, queue: :command_execution, max_attempts: 1

  alias EdgeAgent.Commands
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.info("CommandExecutionWorker started")

    # Process the entire queue
    Commands.process_command_queue()

    Logger.info("CommandExecutionWorker completed, dying")
    :ok
  end
end
