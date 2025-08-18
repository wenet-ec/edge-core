# edge_agent/lib/edge_agent/commands/workers/command_report_scheduler.ex
defmodule EdgeAgent.Commands.Workers.CommandReportScheduler do
  @moduledoc """
  Periodic worker that safely starts CommandReportWorker if needed.
  
  Acts as a safety net to ensure completed command executions get reported
  while respecting the single-worker constraint via maybe_start_report_worker/0.
  
  This scheduler prevents multiple report workers from running simultaneously
  and ensures that completed executions are eventually reported even if the 
  immediate trigger mechanism fails.
  """

  use Oban.Worker, queue: :command_scheduling, max_attempts: 1

  alias EdgeAgent.Commands
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.debug("CommandReportScheduler checking for completed executions")
    
    # Uses existing safety mechanism - won't create worker if one exists
    # This respects the single-worker constraint for reporting
    Commands.maybe_start_report_worker()
    
    Logger.debug("CommandReportScheduler completed")
    :ok
  end
end