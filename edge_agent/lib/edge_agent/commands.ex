# edge_agent/lib/edge_agent/commands.ex
defmodule EdgeAgent.Commands do
  @moduledoc """
  The Commands context.
  """

  import Ecto.Query, warn: false

  alias EdgeAgent.Commands.CommandExecution
  alias EdgeAgent.Commands.ExecutionRegistry
  alias EdgeAgent.Commands.Forms.CreateCommandExecutionForm
  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.Repo

  require Logger

  def list_command_executions do
    Repo.all(CommandExecution)
  end

  def get_command_execution(id) do
    case Repo.get(CommandExecution, id) do
      nil -> {:error, :not_found}
      execution -> {:ok, execution}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def create_command_execution_and_enqueue_worker(params \\ %{}) do
    with {:ok, attrs} <- CreateCommandExecutionForm.changeset(params),
         {:ok, command_execution} <- create_command_execution(attrs) do
      # Trigger enqueue worker (Oban's unique constraint prevents duplicates)
      enqueue_worker(
        EdgeAgent.Commands.Workers.ExecutionEnqueueWorker,
        "ExecutionEnqueueWorker"
      )

      {:ok, command_execution}
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

    start_time = System.monotonic_time(:millisecond)
    timeout_ms = execution.timeout || :infinity

    result =
      try do
        task =
          Task.async(fn ->
            System.cmd("/usr/local/bin/hostscript", [execution.command_text])
          end)

        # Register task for potential cancellation
        ExecutionRegistry.register(execution.id, task.pid)

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
      after
        # Always unregister after completion/timeout/crash
        ExecutionRegistry.unregister(execution.id)
      end

    {output, exit_code} =
      case result do
        {:ok, out, code} -> {out, code}
        {:timeout, out, code} -> {out, code}
        {:error, out, code} -> {out, code}
      end

    duration = System.monotonic_time(:millisecond) - start_time

    Logger.info("Command #{execution.id} completed with exit code: #{exit_code}")

    {:ok, _updated_execution} =
      update_command_execution(execution, %{
        status: "completed",
        output: output,
        exit_code: exit_code,
        completed_at: DateTime.utc_now()
      })

    # Categorize result
    exec_result =
      cond do
        exit_code == 0 -> :success
        exit_code == 124 -> :timeout
        exit_code > 0 -> :failure
        true -> :unknown
      end

    :telemetry.execute(
      [:edge_agent, :commands, :execution, :completed],
      %{duration: duration, exit_code: exit_code, count: 1, total: 1},
      %{result: exec_result}
    )

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
      batch_size = length(completed_executions)
      result = report_executions(completed_executions)

      status =
        case result do
          :ok -> :success
          :error -> :failure
        end

      :telemetry.execute(
        [:edge_agent, :commands, :report],
        %{batch_size: batch_size, count: 1, total: 1},
        %{status: status}
      )

      result
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

        :telemetry.execute(
          [:edge_agent, :commands, :execution, :enqueued],
          %{count: 1, total: 1},
          %{status: :success}
        )

        :ok

      {:error, %Ecto.Changeset{errors: [unique: _]}} ->
        # Already enqueued - this is fine, Oban's unique constraint prevents duplicates
        Logger.debug("Execution #{execution.id} already enqueued, skipped")

        :telemetry.execute(
          [:edge_agent, :commands, :execution, :enqueued],
          %{count: 1, total: 1},
          %{status: :duplicate}
        )

        :ok

      {:error, reason} ->
        Logger.warning("Failed to enqueue execution #{execution.id}: #{inspect(reason)}")

        :telemetry.execute(
          [:edge_agent, :commands, :execution, :enqueued],
          %{count: 1, total: 1},
          %{status: :failure}
        )

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

        {:error, {:http_error, status, body}} when status in [404, 422] ->
          # 404: Execution deleted on admin side
          # 422: Validation error (execution already completed, can't be updated)
          # Discard the execution since it can't be reported anymore
          Logger.warning(
            "Admin rejected update for execution #{execution.id} with HTTP #{status}: #{inspect(body)}. Discarding execution."
          )
          delete_execution_after_report(execution)
          {:cont, :ok}

        {:error, reason} ->
          # Network/connectivity error or other HTTP errors - stop and retry later
          Logger.warning("Failed to report execution #{execution.id}: #{inspect(reason)}")
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

  @doc """
  Cancels a command execution.

  Handles three scenarios:
  1. Pending (not running) - Updates to completed with "cancelled" message
  2. Pending (currently running) - Kills task and updates to completed
  3. Completed - No action taken

  ## Parameters
    - execution: CommandExecution struct

  ## Returns
    - `{:ok, result_map}` - Cancellation result with details
  """
  def cancel_execution(execution) do
    case execution.status do
      "pending" ->
        # Try to kill running task if executing
        task_kill_result =
          case ExecutionRegistry.get_task(execution.id) do
            nil ->
              Logger.debug("Execution #{execution.id} not currently running, marking as cancelled")
              :task_not_running

            task_pid ->
              Logger.info("Killing running task for execution #{execution.id}")
              Process.exit(task_pid, :kill)
              :task_killed
          end

        # Cancel Oban job (prevents future execution)
        oban_result = cancel_oban_job(execution.id)

        # Update execution to cancelled
        {:ok, _updated} =
          update_command_execution(execution, %{
            status: "completed",
            output: "Command cancelled",
            exit_code: 143,
            completed_at: DateTime.utc_now()
          })

        Logger.info("Execution #{execution.id} cancelled successfully")

        {:ok,
         %{
           action: :cancelled,
           task_kill: task_kill_result,
           oban_result: oban_result
         }}

      "completed" ->
        Logger.debug("Execution #{execution.id} already completed, ignoring cancel request")
        {:ok, %{action: :already_completed}}
    end
  end

  defp cancel_oban_job(execution_id) do
    import Ecto.Query

    # Find and cancel Oban job for this execution
    query =
      from(j in Oban.Job,
        where: j.queue == "command_execution",
        where: j.worker == "EdgeAgent.Commands.Workers.CommandExecutionWorker",
        where: fragment("?->>'execution_id' = ?", j.args, ^execution_id),
        where: j.state in ["available", "scheduled", "executing"]
      )

    case Oban.cancel_all_jobs(query) do
      {:ok, 1} ->
        Logger.debug("Cancelled Oban job for execution #{execution_id}")
        :job_cancelled

      {:ok, 0} ->
        Logger.debug("No Oban job found for execution #{execution_id}")
        :job_not_found

      {:ok, count} when count > 1 ->
        Logger.warning("Cancelled #{count} Oban jobs for execution #{execution_id} (expected 1)")
        :job_cancelled
    end
  end
end
