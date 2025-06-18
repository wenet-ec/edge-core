# edge_admin/lib/edge_admin/vpn/workers/auto_reconnecting_worker.ex
defmodule EdgeAdmin.VPN.Workers.AutoReconnectingWorker do
  @moduledoc """
  Oban worker that attempts to reconnect to VPN when disconnected.
  """

  use Oban.Worker, queue: :vpn, max_attempts: 3

  alias EdgeAdmin.VPN

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case VPN.attempt_auto_reconnection() do
      :ok ->
        :ok

      :skipped ->
        :ok

      {:error, reason} ->
        Logger.error("VPN auto-reconnection failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
