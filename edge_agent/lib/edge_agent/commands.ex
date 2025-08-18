# edge_agent/lib/edge_agent/commands.ex
defmodule EdgeAgent.Commands do
  @moduledoc """
  The Commands context.
  """

  import Ecto.Query, warn: false
  alias EdgeAgent.Repo
  alias EdgeAgent.Commands.CommandExecution
  alias EdgeAgent.Commands.Workers.CommandExecutionWorker
  alias EdgeAgent.AdminClient

  require Logger

  def list_command_executions do
    Repo.all(CommandExecution)
  end

  def get_command_execution!(id), do: Repo.get!(CommandExecution, id)

  def create_command_execution_and_maybe_start_worker(attrs \\ %{}) do
    case create_command_execution(attrs) do
      {:ok, command_execution} ->
        maybe_start_execution_worker()
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

    # After all pending processed, trigger reporting if needed
    maybe_start_report_worker()

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

  def maybe_start_execution_worker do
    maybe_start_worker(CommandExecutionWorker, "CommandExecutionWorker")
  end

  def maybe_start_report_worker do
    maybe_start_worker(EdgeAgent.Commands.Workers.CommandReportWorker, "CommandReportWorker")
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

    case System.cmd("/usr/local/bin/hostscript", [execution.command_text]) do
      {output, exit_code} ->
        Logger.info("Command #{execution.id} completed with exit code: #{exit_code}")

        {:ok, updated_execution} =
          update_command_execution(execution, %{
            status: "completed",
            output: output,
            exit_code: exit_code,
            completed_at: DateTime.utc_now()
          })

        updated_execution

      error ->
        Logger.error("Command #{execution.id} execution failed: #{inspect(error)}")

        {:ok, updated_execution} =
          update_command_execution(execution, %{
            status: "completed",
            output: "Execution failed: #{inspect(error)}",
            exit_code: -1,
            completed_at: DateTime.utc_now()
          })

        updated_execution
    end
  end

  defp report_executions(executions) do
    Logger.info("Attempting to report #{length(executions)} executions to admin")

    Enum.reduce_while(executions, :ok, fn execution, _acc ->
      params = %{
        status: execution.status,
        output: execution.output,
        exit_code: execution.exit_code,
        completed_at: execution.completed_at
      }

      case AdminClient.update_command_execution(execution.id, params) do
        :ok ->
          Logger.debug("Successfully reported execution #{execution.id}")

          # Delete the execution from local database after successful report
          case delete_command_execution(execution) do
            {:ok, _deleted_execution} ->
              Logger.debug("Deleted execution #{execution.id} from local database")

            {:error, changeset} ->
              Logger.warning(
                "Failed to delete execution #{execution.id}: #{inspect(changeset.errors)}"
              )
          end

          {:cont, :ok}

        {:error, reason} ->
          Logger.warning("Failed to report execution #{execution.id}: #{inspect(reason)}")

          # Don't process remaining executions
          # Let next cron run retry this and subsequent executions
          {:halt, :error}
      end
    end)
  end

  defp maybe_start_worker(worker_module, worker_name) do
    # Check if there's already a worker of this type scheduled/running
    worker_class = "EdgeAgent.Commands.Workers.#{worker_name}"

    existing_jobs =
      Oban.Job
      |> where([j], j.worker == ^worker_class)
      |> where([j], j.state in ["available", "executing", "retryable"])
      |> Repo.all()

    if Enum.empty?(existing_jobs) do
      Logger.debug("No #{worker_name} running, starting one")

      %{}
      |> worker_module.new()
      |> Oban.insert()
      |> case do
        {:ok, _job} ->
          Logger.debug("#{worker_name} started successfully")

        {:error, reason} ->
          Logger.error("Failed to start #{worker_name}: #{inspect(reason)}")
      end
    else
      Logger.debug("#{worker_name} already running, skipping")
    end
  end

  defp get_pending_executions do
    from(ce in CommandExecution,
      where: ce.status == "pending",
      # FIFO order
      order_by: [asc: ce.inserted_at]
    )
    |> Repo.all()
  end

  defp get_completed_executions do
    from(ce in CommandExecution,
      where: ce.status == "completed",
      # OLDEST FIRST - maintains execution order
      order_by: [asc: ce.inserted_at]
    )
    |> Repo.all()
  end
end
