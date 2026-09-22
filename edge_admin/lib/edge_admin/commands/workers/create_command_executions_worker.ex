# edge_admin/lib/edge_admin/commands/workers/create_command_executions_worker.ex
defmodule EdgeAdmin.Commands.Workers.CreateCommandExecutionsWorker do
  @moduledoc """
  Worker that creates command executions in bulk.

  Delegates execution creation to the Commands context. Executions are created
  for all matching nodes in `pending` status; health filtering happens during
  delivery.
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
