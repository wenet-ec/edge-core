# edge_admin/lib/edge_admin/events/webhooks/filters/webhook_filters.ex
defmodule EdgeAdmin.Events.Webhooks.Filters.WebhookFilters do
  @moduledoc """
  Webhook listing filter helpers.

  Webhooks have a custom `event_type` filter that returns only webhooks whose
  `subscribed_events` list contains the given event type. It's applied
  Elixir-side as a post-query list filter rather than via Ecto, so it lives
  here rather than as a query builder. The same shape is used by
  `EdgeAdmin.Events.Webhooks.fan_out/1` so the two paths can't drift.
  """

  alias EdgeAdmin.Events.Webhooks.Schemas.Webhook

  @doc """
  Pops the `event_type` filter out of a params map. Accepts a string or
  rejects anything else (returns `nil`). Returns `{event_type, remaining_params}`.
  """
  @spec pop_event_type(map()) :: {String.t() | nil, map()}
  def pop_event_type(params) do
    case Map.pop(params, "event_type") do
      {nil, rest} -> {nil, rest}
      {value, rest} when is_binary(value) -> {value, rest}
      {_other, rest} -> {nil, rest}
    end
  end

  @doc """
  Filters a list of webhooks to those whose `subscribed_events` contains the
  given event type. Pass `nil` to no-op (returns the list unchanged).
  """
  @spec filter_by_event_type([Webhook.t()], String.t() | nil) :: [Webhook.t()]
  def filter_by_event_type(webhooks, nil), do: webhooks

  def filter_by_event_type(webhooks, event_type) when is_binary(event_type) do
    Enum.filter(webhooks, fn webhook ->
      event_type in webhook.subscribed_events
    end)
  end
end
