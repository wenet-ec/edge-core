# edge_admin/lib/edge_admin/commands/workers/targeted_dispatch_worker.ex
defmodule EdgeAdmin.Commands.Workers.TargetedDispatchWorker do
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
          "target_node_ids" => target_node_ids
        }
      }) do
    case Commands.create_executions_for_target_nodes(command_id, target_node_ids) do
      {:ok, _executions} ->
        :ok

      {:partial_success, %{successes: _successes, errors: _errors}} ->
        :ok
    end
  end
end
