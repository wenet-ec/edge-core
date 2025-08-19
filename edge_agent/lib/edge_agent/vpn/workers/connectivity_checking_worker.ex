# edge_agent/lib/edge_agent/vpn/workers/connectivity_checking_worker.ex
defmodule EdgeAgent.VPN.Workers.ConnectivityCheckingWorker do
  @moduledoc """
  EdgeAgent worker for VPN connectivity checking.

  This worker monitors VPN connectivity and updates the connection status.
  It uses EdgeAgent.VPN context for app-specific functionality.
  """

  use Oban.Worker, queue: :vpn, max_attempts: 1

  alias EdgeAgent.VPN

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.debug("Starting EdgeAgent VPN connectivity check")

    try do
      result = VPN.check_and_update_connectivity()

      case result do
        :ok ->
          Logger.debug("EdgeAgent connectivity check completed successfully")
          :ok

        {:error, reason} ->
          Logger.warning("EdgeAgent connectivity check failed: #{inspect(reason)}")
          {:error, reason}
      end
    catch
      error ->
        Logger.error("EdgeAgent connectivity check crashed: #{inspect(error)}")
        {:error, error}
    end
  end
end
