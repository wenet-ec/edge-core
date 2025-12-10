# edge_agent/lib/edge_agent/commands.ex
defmodule EdgeAgent.Commands do
  @moduledoc """
  The Commands context.
  """

  import Ecto.Query, warn: false

  alias EdgeAgent.Commands.CommandExecution
  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.Commands.Workers.CommandExecutionWorker
  alias EdgeAgent.Repo

  require Logger

  def list_command_executions do
    Repo.all(CommandExecution)
  end

  def get_command_execution!(id), do: Repo.get!(CommandExecution, id)

  def create_command_execution_and_enqueue_worker(attrs \\ %{}) do
    case create_command_execution(attrs) do
      {:ok, command_execution} ->
        # Trigger execution worker (Oban's unique constraint prevents duplicates)
        enqueue_worker(CommandExecutionWorker, "CommandExecutionWorker")
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

  def process_command_queue do
    Logger.debug("Starting command queue processing with lazy querying")

    # Use lazy querying to handle race conditions
    process_pending_commands_loop()

    # After all pending processed, trigger reporting (Oban's unique constraint prevents duplicates)
    enqueue_worker(EdgeAgent.Commands.Workers.CommandReportWorker, "CommandReportWorker")

    Logger.debug("Command queue processing completed")
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


  defp process_pending_commands_loop do
    # Query fresh each iteration - fixes race conditions!
    pending_executions = get_pending_executions()

    if Enum.empty?(pending_executions) do
      Logger.debug("No pending executions found")
      :ok
    else
      Logger.debug("Processing #{length(pending_executions)} pending executions")

      # Execute each command sequentially (no reporting here!)
      Enum.each(pending_executions, fn execution ->
        execute_single_command(execution)
      end)

      # Recurse to check for new commands that arrived during execution
      process_pending_commands_loop()
    end
  end

  defp execute_single_command(execution) do
    Logger.info("Executing command: #{execution.id}")

    {output, exit_code} = System.cmd("/usr/local/bin/hostscript", [execution.command_text])

    Logger.info("Command #{execution.id} completed with exit code: #{exit_code}")

    {:ok, updated_execution} =
      update_command_execution(execution, %{
        status: "completed",
        output: output,
        exit_code: exit_code,
        completed_at: DateTime.utc_now()
      })

    updated_execution
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
  defp enqueue_worker(worker_module, worker_name) do
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
