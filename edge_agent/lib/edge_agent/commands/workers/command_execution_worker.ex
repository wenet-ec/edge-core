# edge_agent/lib/edge_agent/commands/workers/command_execution_worker.ex
defmodule EdgeAgent.Commands.Workers.CommandExecutionWorker do
  @moduledoc """
  Event-triggered worker that processes command queue sequentially with lazy querying.

  Spawned when new commands arrive and no worker exists.
  Uses lazy querying to handle race conditions where new commands arrive during execution.
  Only focuses on execution - reporting is handled separately by CommandReportWorker.
  """

  use Oban.Worker, queue: :command_execution, max_attempts: 1

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
