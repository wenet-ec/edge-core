# edge_admin/lib/edge_admin/events/views/event_view.ex
defmodule EdgeAdmin.Events.Views.EventView do
  @moduledoc """
  Public-facing renders for event publish actions shared by REST and MCP.
  """

  @spec render_test(map()) :: map()
  def render_test(envelope) when is_map(envelope) do
    %{
      published: true,
      event: envelope
    }
  end
end
