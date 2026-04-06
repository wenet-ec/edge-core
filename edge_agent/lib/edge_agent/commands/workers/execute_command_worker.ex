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
  alias EdgeAgent.Commands.Workers.ReportExecutionWorker
  alias EdgeAgent.Repo

  require Logger

  defp expired?(%{expired_at: nil}), do: false
  defp expired?(%{expired_at: expired_at}), do: DateTime.compare(expired_at, DateTime.utc_now()) != :gt

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"execution_id" => execution_id}}) do
    execution = Repo.get(CommandExecution, execution_id)

    if is_nil(execution) do
      Logger.warning("Execution #{execution_id} not found, skipping")
      :ok
    else
      cond do
        execution.status != "pending" ->
          Logger.debug("Execution #{execution_id} already processed (status: #{execution.status}), skipping")
          :ok

        expired?(execution) ->
          Logger.info("Execution #{execution_id} expired before running, marking expired")
          {:ok, _} = Commands.update_command_execution(execution, %{status: "expired"})

          Commands.enqueue_worker(
            ReportExecutionWorker,
            "ReportExecutionWorker"
          )

          :ok

        true ->
          Commands.execute_single_command(execution)

          Commands.enqueue_worker(
            ReportExecutionWorker,
            "ReportExecutionWorker"
          )

          :ok
      end
    end
  end
end
