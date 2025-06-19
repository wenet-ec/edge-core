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

  @doc """
  Returns the list of command_executions.

  ## Examples

      iex> list_command_executions()
      [%CommandExecution{}, ...]

  """
  def list_command_executions do
    Repo.all(CommandExecution)
  end

  @doc """
  Gets a single command_execution.

  Raises `Ecto.NoResultsError` if the Command execution does not exist.

  ## Examples

      iex> get_command_execution!(123)
      %CommandExecution{}

      iex> get_command_execution!(456)
      ** (Ecto.NoResultsError)

  """
  def get_command_execution!(id), do: Repo.get!(CommandExecution, id)

  @doc """
  Creates a command_execution and maybe starts worker if none exists.

  This is the main entry point called by the HTTP controller.
  """
  def create_command_execution_and_maybe_start_worker(attrs \\ %{}) do
    case create_command_execution(attrs) do
      {:ok, command_execution} ->
        maybe_start_execution_worker()
        {:ok, command_execution}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Creates a command_execution.

  ## Examples

      iex> create_command_execution(%{field: value})
      {:ok, %CommandExecution{}}

      iex> create_command_execution(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_command_execution(attrs \\ %{}) do
    %CommandExecution{}
    |> CommandExecution.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a command_execution.

  ## Examples

      iex> update_command_execution(command_execution, %{field: new_value})
      {:ok, %CommandExecution{}}

      iex> update_command_execution(command_execution, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_command_execution(%CommandExecution{} = command_execution, attrs) do
    command_execution
    |> CommandExecution.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a command_execution.

  ## Examples

      iex> delete_command_execution(command_execution)
      {:ok, %CommandExecution{}}

      iex> delete_command_execution(command_execution)
      {:error, %Ecto.Changeset{}}

  """
  def delete_command_execution(%CommandExecution{} = command_execution) do
    Repo.delete(command_execution)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking command_execution changes.

  ## Examples

      iex> change_command_execution(command_execution)
      %Ecto.Changeset{data: %CommandExecution{}}

  """
  def change_command_execution(%CommandExecution{} = command_execution, attrs \\ %{}) do
    CommandExecution.changeset(command_execution, attrs)
  end

  @doc """
  Processes the entire command queue sequentially (FIFO order).

  Called by CommandExecutionWorker. Executes all pending commands
  and attempts to report results back to admin.
  """
  def process_command_queue do
    Logger.debug("Starting command queue processing")

    # Get all pending executions ordered by creation time (FIFO)
    pending_executions = get_pending_executions()

    if Enum.empty?(pending_executions) do
      Logger.debug("No pending executions found")
      :ok
    else
      Logger.debug("Processing #{length(pending_executions)} pending executions")

      # Execute each command sequentially
      completed_executions =
        Enum.map(pending_executions, fn execution ->
          execute_single_command(execution)
        end)

      # Attempt to report all completed executions
      report_completed_executions(completed_executions)

      Logger.debug("Command queue processing completed")
      :ok
    end
  end

  @doc """
  Reports all unreported completed executions back to admin.

  Called by CommandReportWorker (periodic cleanup).
  """
  def report_unreported_executions do
    Logger.info("Starting unreported executions report")

    # Get all completed executions
    completed_executions = get_completed_executions()

    if Enum.empty?(completed_executions) do
      Logger.debug("No completed executions found")
      :ok
    else
      Logger.info("Reporting #{length(completed_executions)} completed executions")
      report_completed_executions(completed_executions)
    end

    :ok
  end

  # Private helper functions

  defp maybe_start_execution_worker do
    # Check if there's already a CommandExecutionWorker job scheduled/running
    existing_jobs =
      Oban.Job
      |> where([j], j.worker == "EdgeAgent.Commands.Workers.CommandExecutionWorker")
      |> where([j], j.state in ["available", "executing", "retryable"])
      |> Repo.all()

    if Enum.empty?(existing_jobs) do
      Logger.info("No execution worker running, starting new one")

      %{}
      |> CommandExecutionWorker.new()
      |> Oban.insert()
      |> case do
        {:ok, _job} ->
          Logger.info("CommandExecutionWorker started successfully")

        {:error, reason} ->
          Logger.error("Failed to start CommandExecutionWorker: #{inspect(reason)}")
      end
    else
      Logger.debug("CommandExecutionWorker already running, skipping")
    end
  end

  defp get_pending_executions do
    from(ce in CommandExecution,
      where: ce.status == "pending",
      order_by: [asc: ce.inserted_at]
    )
    |> Repo.all()
  end

  defp get_completed_executions do
    from(ce in CommandExecution,
      where: ce.status == "completed",
      order_by: [asc: ce.inserted_at]
    )
    |> Repo.all()
  end

  defp execute_single_command(execution) do
    Logger.info("Executing command: #{execution.id}")

    case System.cmd("/usr/local/bin/hostscript", [execution.command_text]) do
      {output, exit_code} ->
        Logger.info("Command #{execution.id} completed with exit code: #{exit_code}")

        # Update execution with results
        {:ok, updated_execution} =
          update_command_execution(execution, %{
            status: "completed",
            output: output,
            exit_code: exit_code
          })

        updated_execution

      error ->
        Logger.error("Command #{execution.id} execution failed: #{inspect(error)}")

        {:ok, updated_execution} =
          update_command_execution(execution, %{
            status: "completed",
            output: "Execution failed: #{inspect(error)}",
            exit_code: -1
          })

        updated_execution
    end
  end

  defp report_completed_executions(executions) do
    Logger.info("Attempting to report #{length(executions)} executions to admin")

    Enum.each(executions, fn execution ->
      params = %{
        status: execution.status,
        output: execution.output,
        exit_code: execution.exit_code
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

        {:error, reason} ->
          Logger.warning(
            "Failed to report execution #{execution.id}: #{inspect(reason)}, will retry later"
          )

          # Don't delete on failure - let CommandReportWorker retry later
      end
    end)
  end
end
