# edge_admin/test/edge_admin_web/controllers/admins/discovery_controller_test.exs
defmodule EdgeAdminWeb.Controllers.Admins.DiscoveryControllerTest do
  use EdgeAdminWeb.ConnCase, async: true

  describe "GET /api/admins/self/discovery" do
    test "returns admin name only", %{conn: conn} do
      # Get expected values from application config
      expected_admin_name = Application.get_env(:edge_admin, :admin_name)

      conn = get(conn, ~p"/api/admins/self/discovery")

      assert json_response(conn, 200) == %{
               "name" => expected_admin_name
             }
    end

    test "admin name has correct prefix", %{conn: conn} do
      conn = get(conn, ~p"/api/admins/self/discovery")
      response = json_response(conn, 200)

      # Admin name should start with "admin-"
      assert String.starts_with?(response["name"], "admin-")
    end

    test "endpoint is publicly accessible without authentication", %{conn: conn} do
      # No authentication headers needed
      conn = get(conn, ~p"/api/admins/self/discovery")

      # Should not return 401 or 403
      assert conn.status == 200
    end
  end
end
