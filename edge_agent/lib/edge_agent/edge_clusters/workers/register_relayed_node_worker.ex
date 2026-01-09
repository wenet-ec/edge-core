defmodule EdgeAgent.EdgeClusters.Workers.RegisterRelayedNodeWorker do
  @moduledoc """
  Oban worker that periodically registers agent to relay gateways.

  Delegates to EdgeAgent.EdgeClusters.Relay.check_and_register/0 for the actual relay logic.
  """

  use Oban.Worker,
    queue: :relayed_node,
    max_attempts: 1,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias EdgeAgent.EdgeClusters.Relay

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    Logger.debug("RegisterRelayedNodeWorker: Starting relay check")

    Relay.check_and_register()

    Logger.debug("RegisterRelayedNodeWorker: Completed relay check")

    :ok
  end
end
