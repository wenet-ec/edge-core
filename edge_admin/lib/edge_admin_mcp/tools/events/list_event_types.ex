# edge_admin/lib/edge_admin_mcp/tools/events/list_event_types.ex
defmodule EdgeAdminMcp.Tools.Events.ListEventTypes do
  @moduledoc """
  List every event type Edge Admin publishes, with a one-line description
  per type.

  Use this when setting up a webhook (`create_webhook`) — the
  `subscribed_events` field rejects unknown event types at create time,
  so picking values from this list avoids round trips through the
  validator. Use `explain_event_type` to drill into a single event's
  full payload shape.

  Returns the list as `%{event_types: [%{type, description}, ...], count}`.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Events.Catalog

  @impl true
  def title, do: "List Event Types"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    event_types = Catalog.list_with_descriptions()
    {:reply, Response.json(Response.tool(), %{event_types: event_types, count: length(event_types)}), frame}
  end
end
