# edge_agent/lib/edge_agent/commands/workflows/command_execution_cancellation.ex
defmodule EdgeAgent.Commands.Workflows.CommandExecutionCancellation do
  @moduledoc "Cancels local command execution work and finalizes its database row."

  import Ecto.Query

  alias EdgeAgent.Commands.ExecutionRegistry
  alias EdgeAgent.Commands.Resources.CommandExecutionResources
  alias EdgeAgent.Commands.Schemas.CommandExecution

  require Logger

  @spec cancel_execution(CommandExecution.t()) :: {:ok, map()}
  def cancel_execution(execution) do
    case CommandExecutionResources.cancel_pending_or_running(execution.id) do
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

  defp cancel_oban_job(execution_id) do
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
end
