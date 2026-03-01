# edge_agent/lib/edge_agent/edge_clusters/workers/register_relayed_node_worker.ex
defmodule EdgeAgent.EdgeClusters.Workers.RegisterRelayedNodeWorker do
  @moduledoc """
  Oban worker that periodically registers agent to relay gateways.

  Only runs when:
  1. RELAY_ENABLED=true
  2. VPN admin URLs are available (not empty list)

  Relay assignment requires VPN connectivity - cannot work with HTTP fallback.
  Delegates to EdgeAgent.EdgeClusters.Relay.check_and_register/0 for the actual relay logic.
  """

  use Oban.Worker,
    queue: :register_relayed_node,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias EdgeAgent.EdgeClusters.Relay
  alias EdgeAgent.Settings

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    if should_run?() do
      Logger.debug("RegisterRelayedNodeWorker: Starting relay check")
      Relay.check_and_register()
      Logger.debug("RegisterRelayedNodeWorker: Completed relay check")
    else
      Logger.debug("RegisterRelayedNodeWorker: Skipping (relay disabled or no VPN admin URLs)")
    end

    :ok
  end

  defp should_run? do
    relay_enabled = Application.get_env(:edge_agent, :relay_enabled, false)
    admin_urls = Settings.get_admin_urls()

    relay_enabled and admin_urls != []
  end
end
