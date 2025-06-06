# edge_agent/test/edge_agent_web/ping_test.exs
defmodule EdgeAgentWeb.PingTest do
  use EdgeAgentWeb.ConnCase, async: true

  describe "GET /ping" do
    test "returns health status with version", %{conn: conn} do
      conn = get(conn, "/ping")

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      assert response["status"] == "ok"
      assert Map.has_key?(response, "version")
    end

    test "has correct content type", %{conn: conn} do
      conn = get(conn, "/ping")

      # The actual header is just "application/json" without charset
      assert get_resp_header(conn, "content-type") == ["application/json"]
    end
  end
end
