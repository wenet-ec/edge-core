# edge_admin/lib/edge_admin/commands/workers/create_command_executions_worker.ex
defmodule EdgeAdmin.Commands.Workers.CreateCommandExecutionsWorker do
  @moduledoc """
  Worker that creates command executions in bulk.

  Receives execution creation args and delegates to `Delivery.create_command_executions/1`
  which handles all validation and filtering logic. Executions are created for ALL
  matching nodes regardless of health status, all with status "pending"; health
  filtering happens later at delivery time.

  Quantum scheduler handles actual delivery via `Delivery.deliver_local_command_executions/0`.
  """

  use Oban.Worker, queue: :execution_creation, max_attempts: 3

  alias EdgeAdmin.Commands.Workflows.Delivery

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case Delivery.create_command_executions(args) do
      {:ok, _executions} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
