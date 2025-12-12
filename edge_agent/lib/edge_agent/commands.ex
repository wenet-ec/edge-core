# edge_agent/lib/edge_agent/commands.ex
defmodule EdgeAgent.Commands do
  @moduledoc """
  The Commands context.
  """

  import Ecto.Query, warn: false

  alias EdgeAgent.Commands.CommandExecution
  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.Repo

  require Logger

  def list_command_executions do
    Repo.all(CommandExecution)
  end

  def get_command_execution!(id), do: Repo.get!(CommandExecution, id)

  def create_command_execution_and_enqueue_worker(attrs \\ %{}) do
    case create_command_execution(attrs) do
      {:ok, command_execution} ->
        # Trigger enqueue worker (Oban's unique constraint prevents duplicates)
        enqueue_worker(
          EdgeAgent.Commands.Workers.ExecutionEnqueueWorker,
          "ExecutionEnqueueWorker"
        )

        {:ok, command_execution}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def create_command_execution(attrs \\ %{}) do
    %CommandExecution{}
    |> CommandExecution.changeset(attrs)
    |> Repo.insert()
  end

  def update_command_execution(%CommandExecution{} = command_execution, attrs) do
    command_execution
    |> CommandExecution.changeset(attrs)
    |> Repo.update()
  end

  def delete_command_execution(%CommandExecution{} = command_execution) do
    Repo.delete(command_execution)
  end

  def change_command_execution(%CommandExecution{} = command_execution, attrs \\ %{}) do
    CommandExecution.changeset(command_execution, attrs)
  end

  def enqueue_pending_executions do
    Logger.debug("Enqueueing pending command executions")

    pending_executions = get_pending_executions()

    if Enum.empty?(pending_executions) do
      Logger.debug("No pending executions to enqueue")
      :ok
    else
      Logger.info("Enqueueing #{length(pending_executions)} pending executions")

      # Enqueue each execution as a separate Oban job
      Enum.each(pending_executions, fn execution ->
        enqueue_execution_job(execution)
      end)

      :ok
    end
  end

  def execute_single_command(execution) do
    Logger.info("Executing command: #{execution.id}")

    timeout_ms = execution.timeout || :infinity

    result =
      try do
        task =
          Task.async(fn ->
            System.cmd("/usr/local/bin/hostscript", [execution.command_text])
          end)

        case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
          {:ok, {output, exit_code}} ->
            {:ok, output, exit_code}

          nil ->
            Logger.warning("Command #{execution.id} timed out after #{execution.timeout}ms")
            {:timeout, "Command timed out after #{execution.timeout} milliseconds", 124}
        end
      rescue
        e ->
          Logger.error("Command #{execution.id} crashed: #{inspect(e)}")
          {:error, "Command crashed: #{Exception.message(e)}", 1}
      end

    {output, exit_code} =
      case result do
        {:ok, out, code} -> {out, code}
        {:timeout, out, code} -> {out, code}
        {:error, out, code} -> {out, code}
      end

    Logger.info("Command #{execution.id} completed with exit code: #{exit_code}")

    {:ok, _updated_execution} =
      update_command_execution(execution, %{
        status: "completed",
        output: output,
        exit_code: exit_code,
        completed_at: DateTime.utc_now()
      })

    :ok
  end

  def report_unreported_executions do
    Logger.info("Starting unreported executions report")

    # Get completed executions ordered by creation time (oldest first)
    completed_executions = get_completed_executions()

    if Enum.empty?(completed_executions) do
      Logger.debug("No completed executions found")
      :ok
    else
      Logger.info("Reporting #{length(completed_executions)} completed executions")
      report_executions(completed_executions)
    end

    :ok
  end

  defp enqueue_execution_job(execution) do
    %{execution_id: execution.id}
    |> EdgeAgent.Commands.Workers.CommandExecutionWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        Logger.debug("Enqueued execution job for #{execution.id}")
        :ok

      {:error, %Ecto.Changeset{errors: [unique: _]}} ->
        # Already enqueued - this is fine, Oban's unique constraint prevents duplicates
        Logger.debug("Execution #{execution.id} already enqueued, skipped")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to enqueue execution #{execution.id}: #{inspect(reason)}")
        :error
    end
  end

  defp report_executions(executions) do
    Logger.info("Attempting to report #{length(executions)} executions to admin")

    Enum.reduce_while(executions, :ok, fn execution, _acc ->
      params = build_report_params(execution)

      case AdminClient.update_command_execution(execution.id, params) do
        :ok ->
          Logger.debug("Successfully reported execution #{execution.id}")
          delete_execution_after_report(execution)
          {:cont, :ok}

        {:error, reason} ->
          Logger.warning("Failed to report execution #{execution.id}: #{inspect(reason)}")
          # Stop processing remaining executions - let next cron retry
          {:halt, :error}
      end
    end)
  end

  defp build_report_params(execution) do
    %{
      status: execution.status,
      output: execution.output,
      exit_code: execution.exit_code,
      completed_at: execution.completed_at && DateTime.to_iso8601(execution.completed_at)
    }
  end

  defp delete_execution_after_report(execution) do
    case delete_command_execution(execution) do
      {:ok, _deleted_execution} ->
        Logger.debug("Deleted execution #{execution.id} from local database")

      {:error, changeset} ->
        Logger.warning(
          "Failed to delete execution #{execution.id}: #{inspect(changeset.errors)}"
        )
    end
  end


  # Enqueues a worker, handling duplicates gracefully
  def enqueue_worker(worker_module, worker_name) do
    %{}
    |> worker_module.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        Logger.debug("#{worker_name} enqueued")
        :ok

      {:error, _changeset} ->
        # Likely duplicate due to unique constraint - this is expected and fine
        Logger.debug("#{worker_name} already exists, skipped")
        :ok
    end
  end

  # Queries command executions by status, ordered by insertion time (FIFO)
  defp get_executions_by_status(status) do
    from(ce in CommandExecution,
      where: ce.status == ^status,
      order_by: [asc: ce.inserted_at]
    )
    |> Repo.all()
  end

  defp get_pending_executions, do: get_executions_by_status("pending")
  defp get_completed_executions, do: get_executions_by_status("completed")
end
