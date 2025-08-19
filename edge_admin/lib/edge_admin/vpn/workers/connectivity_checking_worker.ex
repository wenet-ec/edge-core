# edge_admin/lib/edge_admin/vpn/workers/connectivity_checking_worker.ex
defmodule EdgeAdmin.VPN.Workers.ConnectivityCheckingWorker do
  @moduledoc """
  EdgeAdmin worker for VPN connectivity checking.

  This worker monitors VPN connectivity and updates the connection status.
  It uses EdgeAdmin.VPN context for app-specific functionality.
  """

  use Oban.Worker, queue: :vpn, max_attempts: 1

  alias EdgeAdmin.VPN

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.debug("Starting EdgeAdmin VPN connectivity check")

    try do
      result = VPN.check_and_update_connectivity()

      case result do
        :ok ->
          Logger.debug("EdgeAdmin connectivity check completed successfully")
          :ok

        {:error, reason} ->
          Logger.warning("EdgeAdmin connectivity check failed: #{inspect(reason)}")
          {:error, reason}
      end
    catch
      error ->
        Logger.error("EdgeAdmin connectivity check crashed: #{inspect(error)}")
        {:error, error}
    end
  end
end
