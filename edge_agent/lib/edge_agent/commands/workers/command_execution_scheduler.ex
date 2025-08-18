# edge_agent/lib/edge_agent/commands/workers/command_execution_scheduler.ex
defmodule EdgeAgent.Commands.Workers.CommandExecutionScheduler do
  @moduledoc """
  Periodic worker that safely starts CommandExecutionWorker if needed.
  
  Acts as a safety net to catch any missed command executions while
  respecting the single-worker constraint via maybe_start_execution_worker/0.
  
  This scheduler prevents multiple execution workers from running simultaneously
  and ensures that pending commands are eventually processed even if the 
  immediate trigger mechanism fails.
  """

  use Oban.Worker, queue: :command_scheduling, max_attempts: 1

  alias EdgeAgent.Commands
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.debug("CommandExecutionScheduler checking for pending commands")
    
    # Uses existing safety mechanism - won't create worker if one exists
    # This respects the single-worker constraint and FIFO execution order
    Commands.maybe_start_execution_worker()
    
    Logger.debug("CommandExecutionScheduler completed")
    :ok
  end
end