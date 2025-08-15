# edge_agent/lib/edge_agent/tailscale/workers/connectivity_checking_worker.ex
defmodule EdgeAgent.Tailscale.Workers.ConnectivityCheckingWorker do
  @moduledoc """
  EdgeAgent worker for Tailscale connectivity checking.

  This worker monitors VPN connectivity and updates the connection status.
  It uses EdgeAgent.Tailscale adapter for app-specific functionality.
  """

  use Oban.Worker, queue: :vpn, max_attempts: 1

  alias EdgeAgent.Tailscale
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.debug("Starting EdgeAgent Tailscale connectivity check")

    try do
      result = Tailscale.check_and_update_connectivity()

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
