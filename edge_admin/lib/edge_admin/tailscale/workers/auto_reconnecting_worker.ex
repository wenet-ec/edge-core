# edge_admin/lib/edge_admin/tailscale/workers/auto_reconnecting_worker.ex
defmodule EdgeAdmin.Tailscale.Workers.AutoReconnectingWorker do
  @moduledoc """
  Oban worker that attempts to reconnect to Tailscale VPN when disconnected.

  This worker runs periodically (every 60 seconds) to check if auto-reconnection
  should be attempted. It only attempts reconnection when:
  - Status is :disconnected
  - manual_disconnect is false (user hasn't manually disconnected)

  The worker uses enrollment keys for reconnection attempts.
  """

  use Oban.Worker, queue: :vpn, max_attempts: 1

  alias EdgeAdmin.Tailscale

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Tailscale.attempt_auto_reconnection() do
      :ok ->
        :ok

      :skipped ->
        :ok

      {:error, reason} ->
        Logger.error("Tailscale auto-reconnection failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
