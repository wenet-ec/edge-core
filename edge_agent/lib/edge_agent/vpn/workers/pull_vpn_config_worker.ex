# edge_agent/lib/edge_agent/vpn/workers/pull_vpn_config_worker.ex
defmodule EdgeAgent.Vpn.Workers.PullVpnConfigWorker do
  @moduledoc """
  Worker that pulls latest VPN configuration from Netmaker server.

  Triggered by:
  - Cron scheduler every 24 hours

  Runs `netclient pull` to fetch full configuration from server via HTTP API,
  bypassing MQTT. Ensures WireGuard interface is updated with all networks
  and addresses. Acts as a safety net for MQTT message loss.

  Can be disabled via PULL_VPN_CONFIG_ENABLED=false for resource-starved machines
  where netclient pull causes disruptive WireGuard interface resets. MQTT retained
  messages provide eventual consistency when this is disabled.

  Uses Oban's unique constraint to ensure only one pull runs at a time.
  """

  use Oban.Worker,
    queue: :pull_vpn_config,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: [:available, :scheduled]
    ]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    if Application.get_env(:edge_agent, :pull_vpn_config_enabled, true) do
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
    else
      Logger.debug("PullVpnConfigWorker skipped (PULL_VPN_CONFIG_ENABLED=false)")
      :ok
    end
  end
end
