# test/edge_admin_web/health_test.exs
defmodule EdgeAdminWeb.HealthTest do
  use EdgeAdminWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns 200 when all checks pass", %{conn: conn} do
      conn = get(conn, "/health")
      assert json_response(conn, 200)
    end

    test "health check returns proper structure", %{conn: conn} do
      conn = get(conn, "/health")
      response = json_response(conn, 200)

      # PlugCheckup returns an array of check results
      assert is_list(response)
      assert length(response) > 0

      # Each check should have these fields
      first_check = List.first(response)
      assert Map.has_key?(first_check, "name")
      assert Map.has_key?(first_check, "healthy")
      assert Map.has_key?(first_check, "error")
      assert Map.has_key?(first_check, "time")
    end

    test "includes NOOP check", %{conn: conn} do
      conn = get(conn, "/health")
      response = json_response(conn, 200)

      # Find the NOOP check in the response array
      noop_check = Enum.find(response, fn check -> check["name"] == "NOOP" end)

      assert noop_check != nil
      assert noop_check["healthy"] == true
      assert noop_check["error"] == nil
    end

    test "all checks are healthy", %{conn: conn} do
      conn = get(conn, "/health")
      response = json_response(conn, 200)

      # Verify all checks are healthy
      healthy_checks = Enum.all?(response, fn check -> check["healthy"] == true end)
      assert healthy_checks
    end
  end
end
