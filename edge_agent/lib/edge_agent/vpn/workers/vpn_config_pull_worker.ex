# edge_agent/lib/edge_agent/vpn/workers/vpn_config_pull_worker.ex
defmodule EdgeAgent.Vpn.Workers.VpnConfigPullWorker do
  @moduledoc """
  Worker that pulls latest VPN configuration from Netmaker server.

  Triggered by:
  - Cron scheduler every 30 minutes

  Runs `netclient pull` to fetch full configuration from server via HTTP API,
  bypassing MQTT. Ensures WireGuard interface is updated with all networks
  and addresses, useful after bulk cluster operations.

  Uses Oban's unique constraint to ensure only one pull runs at a time.
  """

  use Oban.Worker,
    queue: :vpn_config_pull,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    Logger.debug("VpnConfigPullWorker started")

    case Nexmaker.Cli.pull() do
      :ok ->
        Logger.debug("VpnConfigPullWorker completed successfully")
        :ok

      {:error, reason} ->
        Logger.warning("VpnConfigPullWorker failed: #{inspect(reason)}")
        # Return :ok so Oban doesn't retry - next cron will handle it
        :ok
    end
  end
end
