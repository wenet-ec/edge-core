# edge_agent/lib/edge_agent/commands/workflows/command_execution_jobs.ex
defmodule EdgeAgent.Commands.Workflows.CommandExecutionJobs do
  @moduledoc "Enqueues Oban workers for command execution operations."

  require Logger

  @spec enqueue_worker(module(), String.t()) :: :ok
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
end
