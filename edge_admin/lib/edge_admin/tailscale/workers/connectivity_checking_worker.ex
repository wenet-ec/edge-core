# edge_admin/lib/edge_admin/tailscale/workers/connectivity_checking_worker.ex
defmodule EdgeAdmin.Tailscale.Workers.ConnectivityCheckingWorker do
  @moduledoc """
  Oban worker that monitors Tailscale VPN connectivity when the connection status is :connected.

  This worker runs periodically (every 60 seconds) to check if the VPN connection
  is still healthy and updates the connection state accordingly. It only performs
  checks when the connection status is :connected to avoid unnecessary work.
  """

  use Oban.Worker, queue: :vpn, max_attempts: 1

  alias EdgeAdmin.Tailscale

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Tailscale.check_and_update_connectivity() do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Tailscale connectivity check failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
