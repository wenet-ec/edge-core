# edge_admin/lib/edge_admin/events/webhooks/workflows/delivery.ex
defmodule EdgeAdmin.Events.Webhooks.Workflows.Delivery do
  @moduledoc "Coordinates delivery of one webhook envelope and maps its outcome to Oban semantics."

  alias EdgeAdmin.Events.Webhooks.Delivery, as: HttpDelivery
  alias EdgeAdmin.Events.Webhooks.Resources.Webhooks

  @doc "Delivers one webhook envelope and returns an Oban-shaped result."
  @spec deliver_event(String.t(), map()) :: :ok | {:error, term()} | {:cancel, term()}
  def deliver_event(webhook_id, envelope) do
    case Webhooks.get(webhook_id) do
      {:error, :not_found} -> {:cancel, :webhook_deleted}
      {:ok, webhook} -> deliver(webhook, envelope)
    end
  end

  defp deliver(webhook, envelope) do
    start = System.monotonic_time()
    result = HttpDelivery.send(webhook, envelope)
    duration = System.monotonic_time() - start
    emit_telemetry(webhook, envelope, result, duration)

    case result do
      :ok -> :ok
      {:recoverable, reason} -> {:error, reason}
      {:terminal, reason} -> {:cancel, {:delivery_failed, reason}}
    end
  end

  defp emit_telemetry(webhook, envelope, result, duration) do
    outcome =
      case result do
        :ok -> :ok
        {:recoverable, _} -> :recoverable
        {:terminal, _} -> :terminal
      end

    :telemetry.execute(
      [:edge_admin, :webhook, :delivery],
      %{duration: duration},
      %{event_type: envelope["type"], result: outcome, webhook_id: webhook.id}
    )
  end
end
