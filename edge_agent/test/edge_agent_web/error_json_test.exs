# edge_agent/test/edge_agent_web/controllers/error_json_test.exs
defmodule EdgeAgentWeb.ErrorJSONTest do
  use EdgeAgentWeb.ConnCase, async: true

  test "renders 404" do
    assert EdgeAgentWeb.ErrorJSON.render("404.json", %{}) ==
             %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert EdgeAgentWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
