# lib/edge_admin/nodes/workers/ephemeral_key_cleanup_worker.ex
defmodule EdgeAdmin.Nodes.Workers.EphemeralKeyCleanupWorker do
  @moduledoc """
  Oban worker that periodically cleans up expired ephemeral enrollment keys.

  This worker:
  1. Finds expired ephemeral keys (based on TTL)
  2. Deletes hosts from Netmaker that were enrolled with these keys
  3. Deletes edge nodes from our DB (if they were registered)
  4. Deletes the enrollment keys from Netmaker
  5. Deletes the ephemeral key tracker from our DB

  Delegates to EdgeAdmin.Nodes.cleanup_ephemeral_keys/0 for the actual cleanup logic.

  Runs on a configurable schedule (default: daily at midnight).
  """

  use Oban.Worker, queue: :key_cleanup, max_attempts: 3

  alias EdgeAdmin.Nodes

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # Check if cleanup is enabled
    if Application.get_env(:edge_admin, :ephemeral_key_cleanup_enabled, true) do
      Logger.info("Starting ephemeral key cleanup")

      result = Nodes.cleanup_ephemeral_keys()

      Logger.info(
        "Ephemeral key cleanup complete: #{result.deleted_keys} keys, " <>
          "#{result.deleted_hosts} hosts, #{result.deleted_nodes} nodes"
      )

      {:ok, result}
    else
      Logger.info("Ephemeral key cleanup is disabled, skipping")
      {:ok, %{deleted_count: 0, skipped: true}}
    end
  end
end
