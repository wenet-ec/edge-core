# edge_agent/lib/edge_agent/vpn/workers/pull_vpn_config_worker.ex
defmodule EdgeAgent.Vpn.Workers.PullVpnConfigWorker do
  @moduledoc """
  Worker that pulls latest VPN configuration from Netmaker server.

  Triggered by:
  - Cron scheduler every 6 hours

  Runs `netclient pull` to fetch full configuration from server via HTTP API,
  bypassing MQTT. Ensures WireGuard interface is updated with all networks
  and addresses. Acts as a safety net for MQTT message loss.

  Uses Oban's unique constraint to ensure only one pull runs at a time.
  """

  use Oban.Worker,
    queue: :pull_vpn_config,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.debug("PullVpnConfigWorker started")

    case Nexmaker.Cli.pull() do
      :ok ->
        Logger.debug("PullVpnConfigWorker completed successfully")
        :ok

      {:error, reason} ->
        Logger.warning("PullVpnConfigWorker failed: #{inspect(reason)}")
        # Return :ok so Oban doesn't retry - next cron will handle it
        :ok
    end
  end
end
