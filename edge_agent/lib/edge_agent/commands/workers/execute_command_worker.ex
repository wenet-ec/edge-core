# edge_agent/lib/edge_agent/commands/workers/execute_command_worker.ex
defmodule EdgeAgent.Commands.Workers.ExecuteCommandWorker do
  @moduledoc """
  Worker that executes a single command.

  Each command execution gets its own worker instance, allowing parallel execution.
  Uses Oban's unique constraint to prevent duplicate execution of the same command.
  Supports timeout per command.
  """

  use Oban.Worker,
    queue: :execute_command,
    max_attempts: 1,
    unique: [
      period: :infinity,
      fields: [:args],
      keys: [:execution_id],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias EdgeAgent.Commands
  alias EdgeAgent.Commands.CommandExecution
  alias EdgeAgent.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"execution_id" => execution_id}}) do
    execution = Repo.get(CommandExecution, execution_id)

    if is_nil(execution) do
      Logger.warning("Execution #{execution_id} not found, skipping")
      :ok
    else
      # Check status - only execute if still pending
      if execution.status == "pending" do
        # Execute command via Commands context
        Commands.execute_single_command(execution)

        # Trigger reporting worker
        Commands.enqueue_worker(
          EdgeAgent.Commands.Workers.ReportExecutionWorker,
          "ReportExecutionWorker"
        )

        :ok
      else
        Logger.debug("Execution #{execution_id} already processed (status: #{execution.status}), skipping")

        :ok
      end
    end
  end
end
