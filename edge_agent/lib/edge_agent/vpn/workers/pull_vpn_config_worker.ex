# edge_agent/lib/edge_agent/vpn/workers/pull_vpn_config_worker.ex
defmodule EdgeAgent.Vpn.Workers.PullVpnConfigWorker do
  @moduledoc """
  Worker that pulls latest VPN configuration from Netmaker server.

  Triggered by:
  - Cron scheduler at the cadence configured by `PULL_VPN_CONFIG_SCHEDULE`
    (default: daily at midnight)

  Runs `netclient pull` to fetch full configuration from server via HTTP API.
  This is a last-resort backstop for DNS recovery after netclient daemon restarts.
  When the daemon restarts (triggered by MQTT messages such as peer updates, host
  updates, or key rotations), it loses its in-memory DNS state and depends on
  receiving a change-triggering MQTT message to reconfigure DNS. If no such change
  arrives, DNS stays broken indefinitely. This periodic pull guarantees recovery
  with a 24-hour upper bound.

  Note: netclient has its own built-in MQTT fallback that fires every 30 seconds
  when the broker is unreachable — this worker is NOT a broker-down recovery
  mechanism. It solely exists to handle the daemon-restart DNS loss case.

  Disable via PULL_VPN_CONFIG_ENABLED=false only on severely resource-starved
  machines where netclient pull causes disruptive WireGuard interface resets.
  Disabling means broken DNS after a daemon restart can persist indefinitely.

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
    if should_run?() do
      Logger.debug("PullVpnConfigWorker started")

      result =
        case EdgeAgent.Vpn.pull() do
          :ok ->
            Logger.debug("PullVpnConfigWorker completed successfully")
            :success

          {:error, reason} ->
            Logger.warning("PullVpnConfigWorker failed: #{inspect(reason)}")
            :failure
        end

      :telemetry.execute([:edge_agent, :vpn, :pull], %{count: 1}, %{result: result})
      :ok
    else
      Logger.debug("PullVpnConfigWorker skipped (PULL_VPN_CONFIG_ENABLED=false)")
      :ok
    end
  end

  defp should_run? do
    Application.get_env(:edge_agent, :pull_vpn_config_enabled, true)
  end
end
