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
  alias EdgeAgent.Commands.Schemas.CommandExecution
  alias EdgeAgent.Commands.Workers.ReportExecutionWorker
  alias EdgeAgent.Repo

  require Logger

  @doc false
  # Public for unit testing. An execution is expired if `expired_at` is set
  # and has already passed. `nil` means no deadline was configured. Equality
  # with "now" counts as expired (compare result is :eq, not :gt). Accepts
  # any map with an `:expired_at` key, but the production caller is always a
  # CommandExecution struct.
  @spec expired?(map()) :: boolean()
  def expired?(%{expired_at: nil}), do: false
  def expired?(%{expired_at: expired_at}), do: DateTime.compare(expired_at, DateTime.utc_now()) != :gt

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"execution_id" => execution_id}}) do
    execution = Repo.get(CommandExecution, execution_id)

    if is_nil(execution) do
      Logger.warning("Execution #{execution_id} not found, skipping")
      :ok
    else
      cond do
        execution.status != :pending ->
          Logger.debug("Execution #{execution_id} already processed (status: #{execution.status}), skipping")
          :ok

        expired?(execution) ->
          Logger.info("Execution #{execution_id} expired before running, marking expired")
          {:ok, _} = Commands.update_command_execution(execution, %{status: :expired})

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
