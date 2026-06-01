# edge_admin/lib/edge_admin/events/webhooks/filters/webhook_filters.ex
defmodule EdgeAdmin.Events.Webhooks.Filters.WebhookFilters do
  @moduledoc """
  Query helpers for webhook listing.

  Webhooks have a custom `event_type` filter that returns only webhooks whose
  `subscribed_events` list contains the given event type. It is applied in the
  database query so the page rows and `Flop.Meta.total_count` are computed from
  the same filtered scope on both Postgres and SQLite.
  """

  import Ecto.Query

  alias EdgeAdmin.Repo

  @doc """
  Pops the `event_type` filter out of a params map. Accepts a string or
  rejects anything else (returns `nil`). Returns `{event_type, remaining_params}`.
  """
  @spec pop_event_type(map()) :: {String.t() | nil, map()}
  def pop_event_type(params) do
    {value, rest} =
      case Map.pop(params, :event_type) do
        {nil, ^params} -> Map.pop(params, "event_type")
        result -> result
      end

    case {value, rest} do
      {nil, rest} -> {nil, rest}
      {value, rest} when is_binary(value) -> {value, rest}
      {_other, rest} -> {nil, rest}
    end
  end

  @doc """
  Adds the `event_type` containment filter to the query. Pass `nil` to no-op.

  Uses adapter-specific SQL because `subscribed_events` is stored as a Postgres
  string array in Postgres mode and as a JSON-backed array in SQLite mode.
  """
  @spec filter_by_event_type(Ecto.Queryable.t(), String.t() | nil) :: Ecto.Query.t()
  def filter_by_event_type(query, nil), do: Ecto.Queryable.to_query(query)

  def filter_by_event_type(query, event_type) when is_binary(event_type) do
    case Repo.__adapter__() do
      Ecto.Adapters.Postgres ->
        from(w in query, where: fragment("? = ANY(?)", ^event_type, w.subscribed_events))

      Ecto.Adapters.SQLite3 ->
        from(w in query,
          where: fragment("EXISTS (SELECT 1 FROM json_each(?) WHERE value = ?)", w.subscribed_events, ^event_type)
        )
    end
  end
end
