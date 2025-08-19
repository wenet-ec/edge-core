# edge_agent/test/edge_agent_web/health_test.exs
defmodule EdgeAgentWeb.HealthTest do
  use EdgeAgentWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns healthy status with proper structure", %{conn: conn} do
      conn = get(conn, "/health")
      response = json_response(conn, 200)

      # Basic structure validation
      assert is_list(response)
      assert length(response) > 0

      # Verify all checks are healthy and have required fields
      Enum.each(response, fn check ->
        assert Map.has_key?(check, "name")
        assert Map.has_key?(check, "healthy")
        assert check["healthy"] == true
      end)

      # Verify NOOP check exists (our specific check)
      noop_check = Enum.find(response, fn check -> check["name"] == "NOOP" end)
      assert noop_check
      assert noop_check["healthy"] == true
    end
  end
end
