# edge_admin/lib/edge_admin/commands/workers/target_nodes_dispatch_worker.ex
defmodule EdgeAdmin.Commands.Workers.TargetNodesDispatchWorker do
  @moduledoc """
  Worker that creates command executions for specific target nodes.

  This worker attempts immediate delivery to target nodes and creates executions
  with appropriate status ('sent' for successful delivery, 'pending' for failed).
  """

  use Oban.Worker, queue: :command_dispatch, max_attempts: 1

  alias EdgeAdmin.Commands

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "command_id" => command_id,
          "node_ids" => node_ids,
          "node_filters" => node_filters
        }
      }) do
    case Commands.create_executions_for_target_nodes(command_id, node_ids, node_filters) do
      {:ok, _executions} -> :ok
      {:partial_success, %{successes: _successes, errors: _errors}} -> :ok
    end
  end
end
