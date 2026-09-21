# edge_admin/lib/edge_admin/view.ex
defmodule EdgeAdmin.View do
  @moduledoc "Shared helpers for canonical domain view rendering."

  alias Ecto.Association.NotLoaded

  @doc "Renders a preloaded association, returning an empty list when it is not loaded."
  @spec render_embedded(NotLoaded.t() | list(), (term() -> term())) :: list()
  def render_embedded(%NotLoaded{}, _renderer), do: []
  def render_embedded(items, renderer) when is_list(items), do: Enum.map(items, renderer)
end
