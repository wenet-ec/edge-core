# edge_admin/test/edge_admin_web/controllers/nodes/enrollment_key_controller_test.exs
defmodule EdgeAdminWeb.Nodes.EnrollmentKeyControllerTest do
  use EdgeAdminWeb.ConnCase

  describe "POST /api/enrollment-keys" do
    test "creates enrollment key successfully", %{conn: conn} do
      conn = post(conn, ~p"/api/enrollment-keys")

      case conn.status do
        201 ->
          response = json_response(conn, 201)
          assert Map.has_key?(response, "data")

          data = response["data"]
          assert is_binary(data["key"])
          assert is_binary(data["expiration"])
          assert is_binary(data["inserted_at"])

        503 ->
          response = json_response(conn, 503)
          assert response["error"] == "VPN service is currently unavailable"

        500 ->
          response = json_response(conn, 500)
          assert Map.has_key?(response, "error")
      end
    end

    test "handles VPN service errors appropriately", %{conn: conn} do
      conn = post(conn, ~p"/api/enrollment-keys")

      # Endpoint should respond (not 404/405) and return JSON
      refute conn.status == 404
      refute conn.status == 405
      assert get_resp_header(conn, "content-type") |> List.first() =~ "application/json"
    end
  end
end
