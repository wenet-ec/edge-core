# edge_agent/lib/edge_agent/tailscale/workers/auto_reconnecting_worker.ex
defmodule EdgeAgent.Tailscale.Workers.AutoReconnectingWorker do
  @moduledoc """
  EdgeAgent worker for Tailscale auto-reconnection.
  Uses EdgeAgent-specific logic for hostname and configuration.
  """

  use Oban.Worker, queue: :vpn, max_attempts: 1

  alias EdgeAgent.Tailscale
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.debug("Starting EdgeAgent Tailscale auto-reconnection check")

    try do
      result = Tailscale.attempt_auto_reconnection()

      case result do
        {:ok, _connection} ->
          Logger.debug("EdgeAgent auto-reconnection completed successfully")
          :ok
        {:error, :already_connected} ->
          Logger.debug("EdgeAgent already connected, no reconnection needed")
          :ok
        {:error, reason} ->
          Logger.warning("EdgeAgent auto-reconnection failed: #{inspect(reason)}")
          {:error, reason}
      end
    catch
      error ->
        Logger.error("EdgeAgent auto-reconnection crashed: #{inspect(error)}")
        {:error, error}
    end
  end
end
