# edge_admin/lib/edge_admin/commands/workers/target_all_dispatch_worker.ex
defmodule EdgeAdmin.Commands.Workers.TargetAllDispatchWorker do
  @moduledoc """
  Worker that creates command executions for all nodes when target_all is true.

  This worker runs in the background to avoid blocking the command creation response.
  Creates all executions with 'pending' status and lets ExecutionRetryWorker handle delivery.
  """

  use Oban.Worker, queue: :command_dispatch, max_attempts: 1

  alias EdgeAdmin.Commands

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"command_id" => command_id, "node_filters" => node_filters}}) do
    case Commands.create_executions_for_target_all(command_id, node_filters) do
      {:ok, _executions} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
