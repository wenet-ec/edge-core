# edge_agent/lib/edge_agent/commands/commands.ex
defmodule EdgeAgent.Commands do
  @moduledoc """
  Command execution context for edge agents.

  Commands are stored locally, claimed by Oban workers, executed through
  `hostscript`, and reported back to Admin. The local state machine is
  `:pending -> :running -> :completed | :expired`; Admin-only states such as
  `:sent` and `:cancelled` are translated at the boundary.
  """

  import Ecto.Query, warn: false

  alias EdgeAgent.Commands.CommandExecutionOutput
  alias EdgeAgent.Commands.CommandExecutionResults
  alias EdgeAgent.Commands.Enums.CommandExecutionStatuses
  alias EdgeAgent.Commands.ExecutionRegistry
  alias EdgeAgent.Commands.Forms.CreateCommandExecutionForm
  alias EdgeAgent.Commands.Schemas.CommandExecution
  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.Repo
  alias EdgeAgent.Settings

  require Logger

  @doc """
  Lists all command executions from the database.

  Returns all executions regardless of status.
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
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def create_command_execution_and_enqueue_worker(params \\ %{}) do
    with {:ok, attrs} <- CreateCommandExecutionForm.changeset(params),
         {:ok, command_execution} <- get_or_create_command_execution(attrs) do
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
          {:ok, CommandExecution.t()} | {:error, Ecto.Changeset.t()} | {:error, {:conflict, String.t()}}
  def create_command_execution(attrs \\ %{}) do
    %CommandExecution{}
    |> CommandExecution.changeset(attrs)
    |> Repo.insert()
    |> Repo.normalize_conflict([:id])
  end

  defp get_or_create_command_execution(attrs) do
    case get_command_execution(attrs["id"]) do
      {:ok, command_execution} ->
        {:ok, command_execution}

      {:error, :not_found} ->
        create_command_execution(attrs)
    end
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
  Enqueues all recoverable command executions as Oban jobs.

  Called periodically to ensure pending commands are processed and to recover
  commands that were running when the Agent previously stopped.
  Oban's unique constraints prevent duplicate job creation.
  """
  @spec enqueue_pending_executions() :: :ok
  def enqueue_pending_executions do
    Logger.debug("Enqueueing recoverable command executions")

    recoverable_executions = get_recoverable_executions()

    if Enum.empty?(recoverable_executions) do
      Logger.debug("No recoverable executions to enqueue")
      :ok
    else
      Logger.info("Enqueueing #{length(recoverable_executions)} recoverable executions")

      Enum.each(recoverable_executions, fn execution ->
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
    {output, exit_code} = run_command(execution)
    duration = System.monotonic_time(:millisecond) - start_time

    Logger.info("Command #{execution.id} completed with exit code: #{exit_code}")

    case complete_running_execution(execution.id, output, exit_code) do
      :ok ->
        :telemetry.execute(
          [:edge_agent, :commands, :execution, :completed],
          %{duration: duration, exit_code: exit_code, count: 1, total: 1},
          %{result: categorize_exit_code(exit_code)}
        )

      :stale ->
        Logger.info("Command #{execution.id} finished after its state was finalized; discarding result")
    end

    :ok
  end

  @doc """
  Atomically claims a pending command execution for local execution.

  Transitions the row from `:pending` to `:running` only when it is still
  pending at write time. Returns the freshly loaded running execution on a
  successful claim, or `:stale` when cancellation, expiry, or another worker
  finalized the row first.
  """
  @spec claim_command_execution(CommandExecution.t()) :: {:ok, CommandExecution.t()} | :stale
  def claim_command_execution(%CommandExecution{id: id}) do
    query = from(ce in CommandExecution, where: ce.id == ^id and ce.status == :pending)
    now = DateTime.truncate(DateTime.utc_now(), :second)

    case Repo.update_all(query, set: [status: :running, updated_at: now]) do
      {1, _} ->
        case Repo.get(CommandExecution, id) do
          %CommandExecution{status: :running} = execution -> {:ok, execution}
          _ -> :stale
        end

      {0, _} ->
        :stale
    end
  end

  @doc false
  @spec truncate_output(String.t() | nil) :: String.t() | nil
  defdelegate truncate_output(output), to: CommandExecutionOutput, as: :truncate

  defp run_command(execution) do
    timeout_ms = execution.timeout || :infinity

    result =
      try do
        task = Task.async(fn -> System.cmd("/usr/local/bin/hostscript", [execution.command_text]) end)
        ExecutionRegistry.register(execution.id, task.pid)

        case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
          {:ok, {output, exit_code}} ->
            {:ok, CommandExecutionOutput.truncate(output), exit_code}

          nil ->
            Logger.warning("Command #{execution.id} timed out after #{execution.timeout}ms")
            {:timeout, "Command timed out after #{execution.timeout} milliseconds", 124}
        end
      rescue
        e ->
          Logger.error("Command #{execution.id} crashed: #{inspect(e)}")
          {:error, "Command crashed: #{Exception.message(e)}", 1}
      after
        ExecutionRegistry.unregister(execution.id)
      end

    case result do
      {:ok, out, code} -> {out, code}
      {:timeout, out, code} -> {out, code}
      {:error, out, code} -> {out, code}
    end
  end

  @doc false
  @spec categorize_exit_code(integer()) :: :success | :timeout | :cancelled | :failure | :unknown
  defdelegate categorize_exit_code(exit_code), to: CommandExecutionResults

  @doc """
  Reports all completed but unreported executions back to admin.

  Attempts to report completed executions in FIFO order (oldest first).
  Stops on network errors and retries later. Deletes executions after successful report
  or when admin returns 404/422 (execution no longer exists or already completed).
  """
  @spec report_unreported_executions() :: :ok
  def report_unreported_executions do
    Logger.info("Starting unreported executions report")

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
      params = CommandExecutionResults.build_report_params(execution)

      case AdminClient.report_command_execution_result(execution.id, params) do
        :ok ->
          Logger.debug("Successfully reported execution #{execution.id}")
          delete_execution_after_report(execution)
          {:cont, :ok}

        {:error, {:http_error, status, body}} when status in [404, 409, 422] ->
          # 404: Execution deleted on admin side
          # 409: Execution already finalized (conflict) — admin has the final state
          # 422: Validation error — execution not in an updatable state
          # All three mean the admin will never accept this result — discard locally
          Logger.warning(
            "Admin rejected update for execution #{execution.id} with HTTP #{status}: #{inspect(body)}. Discarding execution."
          )

          delete_execution_after_report(execution)
          {:cont, :ok}

        {:error, {:request_failed, reason}} ->
          # Transport error — admin is unreachable. Halt the batch; no point
          # attempting the remaining executions until connectivity recovers.
          Logger.warning("Failed to report execution #{execution.id}, admin unreachable: #{inspect(reason)}")
          {:halt, :error}

        {:error, {:http_error, status, body}} ->
          # Admin is up but returned an unexpected status for this specific row.
          # Log and continue — halting the whole batch for one bad row would
          # block all subsequent executions indefinitely.
          Logger.warning(
            "Admin returned unexpected HTTP #{status} for execution #{execution.id}: #{inspect(body)}. Skipping and continuing."
          )

          {:cont, :ok}
      end
    end)
  end

  @doc false
  @spec build_report_params(CommandExecution.t()) :: map()
  defdelegate build_report_params(execution), to: CommandExecutionResults

  defp delete_execution_after_report(execution) do
    case delete_command_execution(execution) do
      {:ok, _deleted_execution} ->
        Logger.debug("Deleted execution #{execution.id} from local database")

      {:error, changeset} ->
        Logger.warning("Failed to delete execution #{execution.id}: #{inspect(changeset.errors)}")
    end
  end

  def enqueue_worker(worker_module, worker_name) do
    %{}
    |> worker_module.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        Logger.debug("#{worker_name} enqueued")
        :ok

      {:error, _changeset} ->
        Logger.debug("#{worker_name} already exists, skipped")
        :ok
    end
  end

  defp get_executions_by_status(statuses) when is_list(statuses) do
    Repo.all(from(ce in CommandExecution, where: ce.status in ^statuses, order_by: [asc: ce.inserted_at]))
  end

  defp get_executions_by_status(status), do: get_executions_by_status([status])
  defp get_recoverable_executions, do: get_executions_by_status(CommandExecutionStatuses.recoverable_statuses())
  defp get_completed_executions, do: get_executions_by_status(:completed)

  @doc """
  Cancels a command execution.

  Pending or running executions are atomically finalized with exit code 143,
  then any running task and queued Oban job are cancelled. Completed, expired,
  or missing rows are treated as already finalized.
  """
  @spec cancel_execution(CommandExecution.t()) :: {:ok, map()}
  def cancel_execution(execution) do
    case cancel_pending_or_running_execution(execution.id) do
      :cancelled ->
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

        # Cancel Oban job (prevents a future execution).
        oban_result = cancel_oban_job(execution.id)

        Logger.info("Execution #{execution.id} cancelled successfully")

        {:ok,
         %{
           action: :cancelled,
           task_kill: task_kill_result,
           oban_result: oban_result
         }}

      :completed ->
        Logger.debug("Execution #{execution.id} already completed, ignoring cancel request")
        {:ok, %{action: :already_completed}}

      :expired ->
        Logger.debug("Execution #{execution.id} already expired, ignoring cancel request")
        {:ok, %{action: :already_expired}}

      :not_found ->
        Logger.debug("Execution #{execution.id} no longer exists, ignoring cancel request")
        {:ok, %{action: :not_found}}
    end
  end

  defp complete_running_execution(execution_id, output, exit_code) do
    query = from(ce in CommandExecution, where: ce.id == ^execution_id and ce.status == :running)
    now = DateTime.truncate(DateTime.utc_now(), :second)

    attrs = [
      status: :completed,
      output: output,
      exit_code: exit_code,
      completed_at: now,
      updated_at: now
    ]

    case Repo.update_all(query, set: attrs) do
      {1, _} -> :ok
      {0, _} -> :stale
    end
  end

  defp cancel_pending_or_running_execution(execution_id) do
    recoverable_statuses = CommandExecutionStatuses.recoverable_statuses()

    query =
      from(ce in CommandExecution,
        where: ce.id == ^execution_id and ce.status in ^recoverable_statuses
      )

    now = DateTime.truncate(DateTime.utc_now(), :second)

    attrs = [
      status: :completed,
      output: "Command cancelled",
      exit_code: 143,
      completed_at: now,
      updated_at: now
    ]

    case Repo.update_all(query, set: attrs) do
      {1, _} ->
        :cancelled

      {0, _} ->
        case Repo.get(CommandExecution, execution_id) do
          nil -> :not_found
          %{status: :completed} -> :completed
          %{status: :expired} -> :expired
        end
    end
  end

  defp cancel_oban_job(execution_id) do
    import Ecto.Query

    # Find and cancel Oban job for this execution. Queue name must match the
    # one declared in ExecuteCommandWorker (`:execute_command`).
    query =
      from(j in Oban.Job,
        where: j.queue == "execute_command",
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

  Fetches already acknowledged `sent` executions and unacknowledged `pending`
  executions from Admin, stores missing local rows, and leaves failed items for
  the next periodic sync.
  """
  @spec sync_unprocessed_command_executions() :: :ok | {:error, term()}
  def sync_unprocessed_command_executions do
    node_id = Settings.get_node_id()

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

    pending_result = sync_pending_executions(node_id)

    sent_count = if match?({:ok, _count}, sent_result), do: elem(sent_result, 1), else: 0
    pending_count = if match?({:ok, _count}, pending_result), do: elem(pending_result, 1), else: 0

    :telemetry.execute(
      [:edge_agent, :commands, :sync],
      %{count: 1, sent_count: sent_count, pending_count: pending_count},
      %{}
    )

    Logger.info(
      "Command sync completed: #{sent_count} sent, #{pending_count} pending (total: #{sent_count + pending_count})"
    )

    :ok
  end

  defp sync_pending_executions(node_id) do
    case AdminClient.list_pending_command_executions() do
      {:ok, %{data: commands, meta: _meta}} ->
        Logger.info("Syncing #{length(commands)} pending command execution(s)")

        Enum.each(commands, fn command ->
          case AdminClient.acknowledge_command_execution(command["id"]) do
            :ok ->
              Logger.debug("Acknowledged command execution: #{command["id"]}")
              store_command_execution_locally(command, node_id)

            {:error, {:http_error, status, _body}} when status in [404, 409] ->
              # 404: execution deleted on admin side
              # 409: execution is no longer in :pending status — it may have been
              #      cancelled/expired, or it may have already been acknowledged
              #      by another path (peer admin, prior sync, etc.). Either way
              #      we should not retry the acknowledge — discard locally.
              Logger.debug(
                "Discarding command execution #{command["id"]} — admin returned HTTP #{status} (deleted or already past :pending)"
              )

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
  end

  defp store_command_execution_locally(command, node_id) do
    attrs = %{
      id: command["id"],
      command_id: command["command_id"],
      node_id: node_id,
      command_text: command["command_text"],
      timeout: command["timeout"],
      expires_at: command["expires_at"],
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
