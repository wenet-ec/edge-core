# edge_agent/lib/edge_agent/commands.ex
defmodule EdgeAgent.Commands do
  @moduledoc """
  Command execution context for edge agents.

  This module handles receiving commands from the admin server, executing them
  via hostscript, and reporting results back. Commands flow through a queue-based
  execution pipeline with cancellation support.

  ## Architecture

  The module uses a **queue-based execution model** with the following components:

  1. **Local Database** - Stores command executions (pending → completed)
  2. **Oban Jobs** - Manages execution queue with uniqueness constraints
  3. **ExecutionRegistry** - Tracks running tasks for cancellation
  4. **AdminClient** - Reports execution results to admin server

  ## Execution Flow

  ```
  1. Admin sends command → Agent creates CommandExecution (status: "pending")
  2. Enqueue Oban job → EnqueueExecutionWorker triggers ExecuteCommandWorker
  3. Worker calls execute_single_command → Runs via /usr/local/bin/hostscript
  4. Execution completes → Updates status to "completed" with output/exit_code
  5. Report to admin → Sends result via AdminClient.update_command_execution_result
  6. Delete local copy → Removes from agent database after successful report
  ```

  ## Command Cancellation

  Commands can be cancelled at any stage:
  - **Pending (not running)** - Marks as cancelled without killing task
  - **Pending (running)** - Kills task via Process.exit and marks cancelled
  - **Completed** - No action (already finished)

  Cancellation involves:
  1. Killing running task (if executing)
  2. Cancelling Oban job (prevents future execution)
  3. Updating status to completed with exit code 143

  ## Reporting

  Executions are reported back to admin in batches:
  - Report ordered by creation time (FIFO)
  - Handle 404/422 errors (execution deleted/completed on admin side)
  - Stop on network errors and retry later
  - Delete local copy after successful report

  ## Key Concepts

  - **CommandExecution**: Database record tracking command state
  - **ExecutionRegistry**: ETS table mapping execution_id → task_pid
  - **Hostscript**: Sandboxed script execution environment
  - **FIFO Ordering**: Commands executed in order received

  ## Examples

      # List all command executions
      iex> Commands.list_command_executions()
      [%CommandExecution{id: "...", status: "pending", ...}]

      # Create and enqueue execution
      iex> Commands.create_command_execution_and_enqueue_worker(%{
        id: "exec-123",
        command_id: "cmd-456",
        node_id: "node-789",
        command_text: "uptime",
        timeout: 30000
      })
      {:ok, %CommandExecution{}}

      # Cancel running execution
      iex> execution = Commands.get_command_execution("exec-123")
      iex> Commands.cancel_execution(execution)
      {:ok, %{action: :cancelled, task_kill: :task_killed, oban_result: :job_cancelled}}

      # Report completed executions to admin
      iex> Commands.report_unreported_executions()
      :ok
  """

  import Ecto.Query, warn: false

  alias EdgeAgent.Commands.CommandExecution
  alias EdgeAgent.Commands.ExecutionRegistry
  alias EdgeAgent.Commands.Forms.CreateCommandExecutionForm
  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.Repo
  alias EdgeAgent.Settings

  require Logger

  @doc """
  Lists all command executions from the database.

  Returns all executions regardless of status (pending or completed).
  """
  @spec list_command_executions() :: [CommandExecution.t()]
  def list_command_executions do
    Repo.all(CommandExecution)
  end

  @doc """
  Gets a command execution by ID.

  Returns `{:ok, execution}` if found, `{:error, :not_found}` otherwise.
  """
  @spec get_command_execution(String.t()) :: {:ok, CommandExecution.t()} | {:error, :not_found}
  def get_command_execution(id) do
    case Repo.get(CommandExecution, id) do
      nil -> {:error, :not_found}
      execution -> {:ok, execution}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  @doc """
  Creates a command execution and enqueues worker for execution.

  This is the primary entry point for creating new command executions.
  Validates params, creates the execution record, and triggers the execution pipeline.
  """
  @spec create_command_execution_and_enqueue_worker(map()) ::
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()}
  def create_command_execution_and_enqueue_worker(params \\ %{}) do
    with {:ok, attrs} <- CreateCommandExecutionForm.changeset(params),
         {:ok, command_execution} <- create_command_execution(attrs) do
      # Trigger enqueue worker (Oban's unique constraint prevents duplicates)
      enqueue_worker(
        EdgeAgent.Commands.Workers.EnqueueExecutionWorker,
        "EnqueueExecutionWorker"
      )

      {:ok, command_execution}
    end
  end

  @doc """
  Creates a command execution record.

  Lower-level function for creating executions without enqueueing workers.
  Most callers should use `create_command_execution_and_enqueue_worker/1` instead.
  """
  @spec create_command_execution(map()) ::
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()}
  def create_command_execution(attrs \\ %{}) do
    %CommandExecution{}
    |> CommandExecution.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a command execution with new attributes.

  Typically used to update status, output, exit_code, and completed_at after execution.
  """
  @spec update_command_execution(CommandExecution.t(), map()) ::
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()}
  def update_command_execution(%CommandExecution{} = command_execution, attrs) do
    command_execution
    |> CommandExecution.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a command execution from the database.

  Used after successfully reporting execution to admin.
  """
  @spec delete_command_execution(CommandExecution.t()) ::
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()}
  def delete_command_execution(%CommandExecution{} = command_execution) do
    Repo.delete(command_execution)
  end

  @doc """
  Returns a changeset for tracking command execution changes.
  """
  @spec change_command_execution(CommandExecution.t(), map()) :: Ecto.Changeset.t()
  def change_command_execution(%CommandExecution{} = command_execution, attrs \\ %{}) do
    CommandExecution.changeset(command_execution, attrs)
  end

  @doc """
  Enqueues all pending command executions as Oban jobs.

  Called periodically to ensure pending commands are processed.
  Oban's unique constraints prevent duplicate job creation.
  """
  @spec enqueue_pending_executions() :: :ok
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

  @doc """
  Executes a single command via hostscript.

  Runs the command in a separate task with timeout support, registers it for cancellation,
  and updates the execution record with output, exit code, and completion time.

  Exit codes:
  - 0: Success
  - 124: Timeout
  - >0: Failure
  - 143: Cancelled (SIGTERM)
  """
  @spec execute_single_command(CommandExecution.t()) :: :ok
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

  @doc """
  Reports all completed but unreported executions back to admin.

  Attempts to report completed executions in FIFO order (oldest first).
  Stops on network errors and retries later. Deletes executions after successful report
  or when admin returns 404/422 (execution no longer exists or already completed).
  """
  @spec report_unreported_executions() :: :ok
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
    |> EdgeAgent.Commands.Workers.ExecuteCommandWorker.new()
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

      case AdminClient.update_command_execution_result(execution.id, params) do
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
        Logger.warning("Failed to delete execution #{execution.id}: #{inspect(changeset.errors)}")
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
    Repo.all(from(ce in CommandExecution, where: ce.status == ^status, order_by: [asc: ce.inserted_at]))
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
        where: j.worker == "EdgeAgent.Commands.Workers.ExecuteCommandWorker",
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

  @doc """
  Syncs unprocessed command executions from admin.

  Fetches both "sent" and "pending" command executions and stores them locally.
  This provides a comprehensive sync mechanism that handles:
  1. Already acknowledged commands (sent) - stores them for execution
  2. Unacknowledged commands (pending) - acknowledges then stores them

  Used by:
  - Bootstrap (initial sync on startup)
  - SyncUnprocessedExecutionWorker (periodic sync when using HTTP fallback)

  ## Flow
  1. Fetch "sent" executions → store locally (already acknowledged)
  2. Fetch "pending" executions → acknowledge with admin → store locally
  3. Skip duplicates (already exist in local DB)
  4. Continue on individual failures (retry on next sync)

  ## Returns
  - `:ok` - Sync completed (success or partial success)
  - `{:error, reason}` - Sync failed completely

  ## Examples

      iex> Commands.sync_unprocessed_command_executions()
      :ok
  """
  @spec sync_unprocessed_command_executions() :: :ok | {:error, term()}
  def sync_unprocessed_command_executions do
    node_id = Settings.get_node_id()

    # Step 1: Sync "sent" executions (already acknowledged)
    sent_result =
      case AdminClient.list_sent_command_executions() do
        {:ok, %{data: commands, meta: _meta}} ->
          Logger.info("Syncing #{length(commands)} sent command execution(s)")

          Enum.each(commands, fn command ->
            store_command_execution_locally(command, node_id)
          end)

          {:ok, length(commands)}

        {:error, reason} ->
          Logger.warning("Failed to list sent command executions: #{inspect(reason)}")
          {:error, reason}
      end

    # Step 2: Sync "pending" executions (need acknowledgment)
    pending_result =
      case AdminClient.list_pending_command_executions() do
        {:ok, %{data: commands, meta: _meta}} ->
          Logger.info("Syncing #{length(commands)} pending command execution(s)")

          Enum.each(commands, fn command ->
            # Acknowledge with admin first (pending → sent)
            case AdminClient.acknowledge_command_execution(command["id"]) do
              :ok ->
                Logger.debug("Acknowledged command execution: #{command["id"]}")
                # Then store locally
                store_command_execution_locally(command, node_id)

              {:error, reason} ->
                Logger.warning(
                  "Failed to acknowledge command execution #{command["id"]}: #{inspect(reason)} - will retry next sync"
                )
            end
          end)

          {:ok, length(commands)}

        {:error, reason} ->
          Logger.warning("Failed to list pending command executions: #{inspect(reason)}")
          {:error, reason}
      end

    # Emit telemetry
    sent_count = if match?({:ok, _count}, sent_result), do: elem(sent_result, 1), else: 0
    pending_count = if match?({:ok, _count}, pending_result), do: elem(pending_result, 1), else: 0

    :telemetry.execute(
      [:edge_agent, :commands, :sync],
      %{sent_count: sent_count, pending_count: pending_count, total: sent_count + pending_count},
      %{}
    )

    Logger.info(
      "Command sync completed: #{sent_count} sent, #{pending_count} pending (total: #{sent_count + pending_count})"
    )

    :ok
  end

  # Private helper: stores a command execution locally
  defp store_command_execution_locally(command, node_id) do
    attrs = %{
      id: command["id"],
      command_id: command["command_id"],
      node_id: node_id,
      command_text: command["command_text"],
      timeout: command["timeout"],
      status: "pending"
    }

    case create_command_execution_and_enqueue_worker(attrs) do
      {:ok, _execution} ->
        Logger.debug("Stored command execution: #{command["id"]}")

      {:error, %Ecto.Changeset{errors: [id: {"has already been taken", _}]}} ->
        Logger.debug("Command execution #{command["id"]} already exists, skipping")

      {:error, changeset} ->
        Logger.warning(
          "Failed to store command execution #{command["id"]}: #{inspect(changeset.errors)} - will retry next sync"
        )
    end
  end
end
