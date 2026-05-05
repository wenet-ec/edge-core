# edge_admin/lib/edge_admin/commands/workers/create_executions_worker.ex
defmodule EdgeAdmin.Commands.Workers.CreateExecutionsWorker do
  @moduledoc """
  Worker that creates command executions in bulk.

  Receives execution creation args and delegates to `Commands.create_command_executions/1`
  which handles all validation and filtering logic. Executions are created for ALL
  matching nodes regardless of health status, all with status "pending"; health
  filtering happens later at delivery time.

  Quantum scheduler handles actual delivery via `Commands.deliver_local_executions/0`.
  """

  use Oban.Worker, queue: :execution_creation, max_attempts: 3

  alias EdgeAdmin.Commands

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case Commands.create_command_executions(args) do
      {:ok, _executions} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
