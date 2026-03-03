# edge_admin/lib/edge_admin/commands/workers/execution_creation_worker.ex
defmodule EdgeAdmin.Commands.Workers.ExecutionCreationWorker do
  @moduledoc """
  Worker that creates command executions in bulk.

  Receives execution creation args and delegates to `Commands.create_command_executions/1`
  which handles all validation and filtering logic. All executions are created with
  status "pending" and filtered to only include healthy nodes.

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
