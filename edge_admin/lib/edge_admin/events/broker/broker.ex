# edge_admin/lib/edge_admin/events/broker/broker.ex
defmodule EdgeAdmin.Events.Broker do
  @moduledoc """
  Broker delivery channel for the event publish path.

  Publishes pre-built CloudEvents envelopes to a configured message broker.
  This module is the broker-side entry point — business logic calls
  `EdgeAdmin.Events.publish/1`, which fans out to this channel (and any
  other delivery channels) via Oban workers.

  The channel is enabled by deployment configuration. When disabled, no broker
  connection is started and events bypass this channel. The selected adapter
  owns connection, routing, and durability semantics.
  """

  alias EdgeAdmin.Events.Broker.AdapterRegistry
  alias EdgeAdmin.Events.Broker.Workers.PublishEventWorker

  require Logger

  @doc """
  Returns `:ok` if the broker connection is healthy, `{:error, reason}` if not.
  Returns `:ok` immediately when the event broker is disabled.
  """
  @spec healthy?() :: :ok | {:error, String.t()}
  def healthy? do
    if enabled?() do
      adapter().healthy?()
    else
      :ok
    end
  end

  @doc """
  Enqueues a pre-built envelope for async broker delivery via Oban.

  Called by `EdgeAdmin.Events.publish/1`. No-op when the broker is disabled.
  """
  @spec enqueue(map()) :: :ok
  def enqueue(envelope) do
    if enabled?() do
      envelope
      |> PublishEventWorker.new()
      |> Oban.insert!()

      :telemetry.execute(
        [:edge_admin, :event_broker, :enqueue],
        %{count: 1},
        %{event_type: envelope["type"]}
      )
    end

    :ok
  end

  @doc """
  Publishes a pre-built CloudEvents envelope directly to the broker adapter.

  Called by `PublishEventWorker` — not intended for direct use in business logic.
  Returns `{:error, reason}` on failure so Oban can retry.
  """
  @spec publish_envelope(map()) :: :ok | {:error, term()}
  def publish_envelope(envelope) do
    mod = adapter()
    adapter_name = adapter_name()
    event_type = envelope["type"]

    start_time = System.monotonic_time()

    result = mod.publish(envelope)

    duration = System.monotonic_time() - start_time

    case result do
      :ok ->
        :telemetry.execute(
          [:edge_admin, :event_broker, :publish],
          %{duration: duration},
          %{adapter: adapter_name, event_type: event_type, result: :ok}
        )

        :ok

      {:error, reason} ->
        Logger.warning("[EventBroker] Failed to publish #{event_type}: #{inspect(reason)}")

        :telemetry.execute(
          [:edge_admin, :event_broker, :publish],
          %{duration: duration},
          %{adapter: adapter_name, event_type: event_type, result: :error}
        )

        {:error, reason}
    end
  end

  defp enabled? do
    Application.get_env(:edge_admin, :event_broker_enabled, false)
  end

  defp adapter, do: AdapterRegistry.module_for(adapter_name())

  defp adapter_name do
    Application.get_env(:edge_admin, :event_broker_adapter)
  end
end
