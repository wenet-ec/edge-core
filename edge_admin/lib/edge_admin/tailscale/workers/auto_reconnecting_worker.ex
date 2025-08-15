# edge_admin/lib/edge_admin/tailscale/workers/auto_reconnecting_worker.ex
defmodule EdgeAdmin.Tailscale.Workers.AutoReconnectingWorker do
  @moduledoc """
  EdgeAdmin worker for Tailscale auto-reconnection.
  Uses EdgeAdmin-specific logic for hostname and configuration.
  """

  use Oban.Worker, queue: :vpn, max_attempts: 1

  alias EdgeAdmin.Tailscale
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.debug("Starting EdgeAdmin Tailscale auto-reconnection check")

    try do
      result = Tailscale.attempt_auto_reconnection()

      case result do
        {:ok, _connection} ->
          Logger.debug("EdgeAdmin auto-reconnection completed successfully")
          :ok
        {:error, :already_connected} ->
          Logger.debug("EdgeAdmin already connected, no reconnection needed")
          :ok
        {:error, reason} ->
          Logger.warning("EdgeAdmin auto-reconnection failed: #{inspect(reason)}")
          {:error, reason}
      end
    catch
      error ->
        Logger.error("EdgeAdmin auto-reconnection crashed: #{inspect(error)}")
        {:error, error}
    end
  end
end
