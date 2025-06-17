# edge_agent/test/edge_agent_web/ping_test.exs
defmodule EdgeAgentWeb.PingTest do
  use EdgeAgentWeb.ConnCase, async: true

  describe "GET /ping" do
    test "returns ok status with version", %{conn: conn} do
      conn = get(conn, "/ping")
      response = json_response(conn, 200)

      assert response["status"] == "ok"
      assert Map.has_key?(response, "version")
    end
  end
end
