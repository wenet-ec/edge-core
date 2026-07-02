# edge_admin/lib/edge_admin_mcp/tools/events/publish_test_event.ex
defmodule EdgeAdminMcp.Tools.Events.PublishTestEvent do
  @moduledoc """
  Publish an `edge.core.test` event through Core's normal event delivery path.

  The event is enqueued for the configured event broker, if enabled, and
  delivered to webhooks whose `subscribed_events` includes `edge.core.test`.
  Use this to verify event delivery plumbing without fabricating a business
  event such as node registration or command completion.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Events
  alias EdgeAdmin.Events.Views.EventView

  @impl true
  def title, do: "Publish Test Event"
  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => false, "openWorldHint" => true}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    {:ok, envelope} = Events.publish_test_event()

    {:reply, Response.json(Response.tool(), EventView.render_test(envelope)), frame}
  end
end
