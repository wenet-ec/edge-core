# edge_admin/test/edge_admin_web/ping_test.exs
defmodule EdgeAdminWeb.PingTest do
  use EdgeAdminWeb.ConnCase, async: true

  describe "GET /ping" do
    test "returns ok status with version", %{conn: conn} do
      conn = get(conn, "/ping")
      response = json_response(conn, 200)

      assert response["status"] == "ok"
      assert Map.has_key?(response, "version")
    end
  end
end
