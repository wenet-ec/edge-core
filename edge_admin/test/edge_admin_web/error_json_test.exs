# test/edge_admin_web/controllers/error_json_test.exs
defmodule EdgeAdminWeb.ErrorJSONTest do
  use EdgeAdminWeb.ConnCase, async: true

  test "renders 404" do
    assert EdgeAdminWeb.ErrorJSON.render("404.json", %{}) ==
             %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert EdgeAdminWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
