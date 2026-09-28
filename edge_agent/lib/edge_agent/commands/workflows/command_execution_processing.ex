# edge_agent/lib/edge_agent/commands/workflows/command_execution_processing.ex
defmodule EdgeAgent.Commands.Workflows.CommandExecutionProcessing do
  @moduledoc "Enqueues recoverable executions and runs command processes."

  alias EdgeAgent.Commands.CommandExecutionOutput
  alias EdgeAgent.Commands.CommandExecutionResults
  alias EdgeAgent.Commands.ExecutionRegistry
  alias EdgeAgent.Commands.Resources.CommandExecutionResources
  alias EdgeAgent.Commands.Schemas.CommandExecution
  alias EdgeAgent.Commands.Workers.ExecuteCommandWorker

  require Logger

  @spec enqueue_pending_executions() :: :ok
  def enqueue_pending_executions do
    Logger.debug("Enqueueing recoverable command executions")
    recoverable_executions = CommandExecutionResources.list_recoverable()

    if Enum.empty?(recoverable_executions) do
      Logger.debug("No recoverable executions to enqueue")
      :ok
    else
      Logger.info("Enqueueing #{length(recoverable_executions)} recoverable executions")
      Enum.each(recoverable_executions, &enqueue_execution_job/1)
      :ok
    end
  end

  @doc "Executes a command through hostscript and records its result."
  @spec execute_single_command(CommandExecution.t()) :: :ok
  def execute_single_command(execution) do
    Logger.info("Executing command: #{execution.id}")

    start_time = System.monotonic_time(:millisecond)
    {output, exit_code} = run_command(execution)
    duration = System.monotonic_time(:millisecond) - start_time

    Logger.info("Command #{execution.id} completed with exit code: #{exit_code}")

    case CommandExecutionResources.complete_running(execution.id, output, exit_code) do
      :ok ->
        :telemetry.execute(
          [:edge_agent, :commands, :execution, :completed],
          %{duration: duration, exit_code: exit_code, count: 1, total: 1},
          %{result: CommandExecutionResults.categorize_exit_code(exit_code)}
        )

      :stale ->
        Logger.info("Command #{execution.id} finished after its state was finalized; discarding result")
    end

    :ok
  end

  defp enqueue_execution_job(execution) do
    %{execution_id: execution.id}
    |> ExecuteCommandWorker.new()
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
        error ->
          Logger.error("Command #{execution.id} crashed: #{inspect(error)}")
          {:error, "Command crashed: #{Exception.message(error)}", 1}
      after
        ExecutionRegistry.unregister(execution.id)
      end

    case result do
      {:ok, output, exit_code} -> {output, exit_code}
      {:timeout, output, exit_code} -> {output, exit_code}
      {:error, output, exit_code} -> {output, exit_code}
    end
  end
end
