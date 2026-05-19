# edge_admin/lib/edge_admin/events/events.ex
defmodule EdgeAdmin.Events do
  @moduledoc """
  Public API for publishing lifecycle events.

  Business logic constructs a typed event struct from `EdgeAdmin.Events.Catalog`
  and calls `publish/1`. Events are dispatched to every configured delivery
  channel — today that's the broker (`EdgeAdmin.Events.Broker`); webhooks and
  other channels plug in here as they're added.

  Publishing is fire-and-forget from the call site's perspective: errors are
  logged inside each channel but never returned to the caller.

  ## Usage

      # In business logic, immediately after the DB write succeeds:
      Events.publish(%Events.Catalog.NodeRegistered{node: node})

  ## Event envelope

  Every published event is wrapped in a CloudEvents 1.0 envelope:

      %{
        "specversion"     => "1.0",
        "id"              => uuid,
        "source"          => "https://github.com/wenet-ec/edge-core",
        "type"            => "node.registered",
        "time"            => iso8601,
        "datacontenttype" => "application/json",
        "corename"        => "prod-us",
        "data"            => %{...}
      }

  `corename` is a CloudEvents extension attribute identifying which core
  instance published the event. Defaults to `"default"` if `CORE_NAME` is
  not set.
  """

  alias EdgeAdmin.Events.Broker
  alias EdgeAdmin.Events.Catalog
  alias EdgeAdmin.Events.Webhooks

  @type event ::
          Catalog.NodeRegistered.t()
          | Catalog.NodeReregistered.t()
          | Catalog.NodeVersionChanged.t()
          | Catalog.NodeStatusChanged.t()
          | Catalog.NodeUpdateTriggered.t()
          | Catalog.CommandExecutionCreated.t()
          | Catalog.CommandExecutionSent.t()
          | Catalog.CommandExecutionCompleted.t()
          | Catalog.CommandExecutionCancelled.t()
          | Catalog.CommandExecutionExpired.t()
          | Catalog.CommandExecutionPruned.t()
          | Catalog.SelfUpdateCompleted.t()
          | Catalog.EnrollmentKeyVerified.t()
          | Catalog.SshUsernameVerified.t()

  @doc """
  Publishes an event to every configured delivery channel.

  Builds a CloudEvents envelope at call time (capturing exact state) and hands
  it to each channel unconditionally — channels short-circuit internally when
  they have nothing to do (broker disabled, no matching webhooks, etc.) and
  own their own queuing, retry, and failure semantics. Always returns `:ok`.

  Per-channel health checks are not exposed through `Events` — operators query
  each channel directly (e.g. `EdgeAdmin.Events.Broker.healthy?/0`) so dashboards
  and health endpoints can report each channel under its own name.
  """
  @spec publish(event()) :: :ok
  def publish(event) do
    envelope = build_envelope(event)
    Broker.enqueue(envelope)
    Webhooks.fan_out(envelope)
    :ok
  end

  @doc false
  # Public for unit testing. Builds the CloudEvents 1.0 envelope from an event
  # struct — captures `id`, `time`, and `corename` at call time, delegates
  # `type` and `data` to the catalog. Not meant for direct use in business
  # logic; call `publish/1` instead.
  @spec build_envelope(event()) :: map()
  def build_envelope(event) do
    %{
      "specversion" => "1.0",
      "id" => Uniq.UUID.uuid4(),
      "source" => "https://github.com/wenet-ec/edge-core",
      "type" => Catalog.event_type(event),
      "time" => DateTime.to_iso8601(DateTime.utc_now()),
      "datacontenttype" => "application/json",
      "corename" => Application.get_env(:edge_admin, :core_name, "default"),
      "data" => Catalog.to_data(event)
    }
  end
end
