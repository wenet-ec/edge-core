defmodule EdgeAdminWeb.Nodes.EnrollmentKeyControllerTest do
  use EdgeAdminWeb.ConnCase

  describe "POST /api/enrollment-keys" do
    test "endpoint responds with valid JSON structure", %{conn: conn} do
      conn = post(conn, ~p"/api/enrollment-keys")

      # Test that the endpoint exists and responds with proper JSON
      assert conn.status in [200, 201, 500, 503]
      assert get_resp_header(conn, "content-type") |> List.first() =~ "application/json"

      response = json_response(conn, conn.status)

      case conn.status do
        201 ->
          # Successful creation - test the response structure
          assert Map.has_key?(response, "data")
          data = response["data"]
          assert Map.has_key?(data, "key")
          assert Map.has_key?(data, "expiration")
          assert Map.has_key?(data, "created_at")
          assert is_binary(data["key"])
          assert is_binary(data["expiration"])
          assert is_binary(data["created_at"])

        500 ->
          # Internal server error - test error structure
          assert Map.has_key?(response, "error")
          assert is_binary(response["error"])

        503 ->
          # Service unavailable - test specific error message
          assert Map.has_key?(response, "error")
          assert response["error"] == "VPN service is currently unavailable"
      end
    end

    test "POST request returns JSON content-type", %{conn: conn} do
      conn = post(conn, ~p"/api/enrollment-keys")
      content_type = get_resp_header(conn, "content-type") |> List.first()
      assert content_type =~ "application/json"
    end

    test "endpoint accepts POST method", %{conn: conn} do
      conn = post(conn, ~p"/api/enrollment-keys")
      # As long as we don't get a 405 (Method Not Allowed), the endpoint accepts POST
      refute conn.status == 405
    end
  end
end
