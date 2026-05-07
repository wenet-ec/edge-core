# edge_admin/lib/edge_admin_mcp/tools/events/explain_event_type.ex
defmodule EdgeAdminMcp.Tools.Events.ExplainEventType do
  @moduledoc """
  Explain a single event type: when it fires + a sample `data` payload
  shape.

  Returns `%{type, description, data_example, reference}`. The
  `data_example` is the shape of the CloudEvents `data` field — the
  outer envelope (specversion, id, source, type, time, corename) is
  documented in `/asyncdoc` and is identical across event types.

  Use when:
  - Setting up a webhook and want to know what the receiver will see for
    a specific subscribed event type.
  - Debugging a handler and need to remember the payload shape.

  For the catalog without payload details, use `list_event_types`.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Events.Catalog

  @impl true
  def title, do: "Explain Event Type"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :event_type, {:required, :string}, min_length: 1
  end

  @impl true
  def execute(%{event_type: event_type}, frame) do
    case Catalog.lookup(event_type) do
      {:ok, entry} ->
        {:reply, Response.json(Response.tool(), entry), frame}

      {:error, :not_found} ->
        {:reply,
         error_response(
           :not_found,
           "Event type \"#{event_type}\" is not in the catalog. Use list_event_types to see all valid types."
         ), frame}
    end
  end
end
