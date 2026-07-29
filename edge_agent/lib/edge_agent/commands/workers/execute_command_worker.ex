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
      states: :incomplete
    ]

  import Ecto.Query

  alias EdgeAgent.Commands
  alias EdgeAgent.Commands.Schemas.CommandExecution
  alias EdgeAgent.Commands.Workers.ReportExecutionWorker
  alias EdgeAgent.Repo

  require Logger

  @doc false
  # Public for unit testing. An execution is expired if `expires_at` is set
  # and has already passed. `nil` means no deadline was configured. Equality
  # with "now" counts as expired (compare result is :eq, not :gt). Accepts
  # any map with an `:expires_at` key, but the production caller is always a
  # CommandExecution struct.
  @spec expired?(map()) :: boolean()
  def expired?(%{expires_at: nil}), do: false
  def expired?(%{expires_at: expires_at}), do: DateTime.compare(expires_at, DateTime.utc_now()) != :gt

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"execution_id" => execution_id}}) do
    execution = Repo.get(CommandExecution, execution_id)

    if is_nil(execution) do
      Logger.warning("Execution #{execution_id} not found, skipping")
      :ok
    else
      case execution.status do
        :pending ->
          if expired?(execution) do
            Logger.info("Execution #{execution_id} expired before running, marking expired")
            mark_expired(execution)

            Commands.enqueue_worker(
              ReportExecutionWorker,
              "ReportExecutionWorker"
            )
          else
            case Commands.claim_command_execution(execution) do
              {:ok, running_execution} ->
                Commands.execute_single_command(running_execution)

                Commands.enqueue_worker(
                  ReportExecutionWorker,
                  "ReportExecutionWorker"
                )

              :stale ->
                Logger.debug("Execution #{execution_id} changed state before it could be claimed, skipping")
            end
          end

          :ok

        :running ->
          # A running row only reaches a fresh worker after Oban recovery or the
          # periodic re-enqueue pass. The Agent deliberately retries it after a
          # crash, so command delivery remains at-least-once.
          Commands.execute_single_command(execution)

          Commands.enqueue_worker(
            ReportExecutionWorker,
            "ReportExecutionWorker"
          )

          :ok

        status ->
          Logger.debug("Execution #{execution_id} already processed (status: #{status}), skipping")
          :ok
      end
    end
  end

  defp mark_expired(execution) do
    query =
      from(ce in CommandExecution,
        where: ce.id == ^execution.id and ce.status == :pending
      )

    now = DateTime.truncate(DateTime.utc_now(), :second)
    Repo.update_all(query, set: [status: :expired, updated_at: now])
  end
end
