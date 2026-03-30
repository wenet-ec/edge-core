# edge_admin/lib/edge_admin/self_updates/workers/trigger_self_update_worker.ex
defmodule EdgeAdmin.SelfUpdates.Workers.TriggerSelfUpdateWorker do
  @moduledoc """
  Worker that processes self-update requests.

  Delegates to SelfUpdates.process_self_update_request/1 for all business logic.
  """

  use Oban.Worker, queue: :self_updates, max_attempts: 3

  alias EdgeAdmin.SelfUpdates

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"request_id" => request_id}}) do
    SelfUpdates.process_self_update_request(request_id)
  end
end
