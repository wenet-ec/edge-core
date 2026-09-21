# edge_admin/test/edge_admin/view_test.exs
defmodule EdgeAdmin.ViewTest do
  use ExUnit.Case, async: true

  alias Ecto.Association.NotLoaded
  alias EdgeAdmin.View

  test "renders each preloaded association item" do
    assert [2, 4] = View.render_embedded([1, 2], &(&1 * 2))
  end

  test "renders an unloaded association as an empty list" do
    assert [] = View.render_embedded(%NotLoaded{}, & &1)
  end
end
