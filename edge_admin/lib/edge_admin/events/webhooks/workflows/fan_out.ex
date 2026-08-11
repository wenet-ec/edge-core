# edge_admin/lib/edge_admin/events/webhooks/workflows/fan_out.ex
defmodule EdgeAdmin.Events.Webhooks.Workflows.FanOut do
  @moduledoc "Enqueues webhook delivery jobs for matching event envelopes."

  alias EdgeAdmin.Events.Webhooks.Resources.Webhooks
  alias EdgeAdmin.Events.Webhooks.Workers.DeliverEventWorker

  require Logger

  @doc "Enqueues one delivery job for every webhook subscribed to the envelope type."
  @spec fan_out(map()) :: :ok
  def fan_out(envelope) do
    max_attempts = Application.get_env(:edge_admin, :webhook_max_attempts, 3)
    count = enqueue_matching_pages(envelope, max_attempts, 1, 0)

    :telemetry.execute(
      [:edge_admin, :webhook, :fan_out],
      %{count: count},
      %{event_type: envelope["type"]}
    )

    :ok
  end

  defp enqueue_matching_pages(envelope, max_attempts, page, count) do
    params = %{"event_type" => envelope["type"], "page" => to_string(page), "page_size" => "1000"}

    case Webhooks.list(params) do
      {:ok, {webhooks, meta}} ->
        Enum.each(webhooks, fn webhook ->
          %{webhook_id: webhook.id, envelope: envelope}
          |> DeliverEventWorker.new(max_attempts: max_attempts)
          |> Oban.insert!()
        end)

        next_count = count + length(webhooks)

        if meta.has_next_page?,
          do: enqueue_matching_pages(envelope, max_attempts, page + 1, next_count),
          else: next_count

      {:error, _meta} ->
        Logger.error("Webhooks fan-out failed for event_type=#{envelope["type"]}")
        count
    end
  end
end
