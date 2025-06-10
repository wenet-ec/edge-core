# edge_admin/test/edge_admin_web/vpn/connection_controller_test.exs
defmodule EdgeAdminWeb.VPN.ConnectionControllerTest do
  use EdgeAdminWeb.ConnCase, async: false

  alias EdgeAdmin.VPN

  setup do
    # Reset the ETS table state between tests
    :ets.delete_all_objects(:vpn_connection)
    {:ok, _} = VPN.create_connection(%{})
    :ok
  end

  describe "GET /api/connections/self" do
    test "returns 200 with connection data when connection exists", %{conn: conn} do
      # Setup connection state
      {:ok, _} = VPN.update_connection(%{
        status: :connected,
        vpn_ip: "100.64.0.10",
        vpn_hostname: "edge-admin",
        connected_at: DateTime.utc_now(),
        manual_disconnect: false
      })

      conn = get(conn, ~p"/api/connections/self")

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      assert response["status"] == "connected"
      assert response["vpn_ip"] == "100.64.0.10"
      assert response["vpn_hostname"] == "edge-admin"
      assert response["manual_disconnect"] == false
      assert Map.has_key?(response, "connected_at")
      assert Map.has_key?(response, "last_checked_at")
    end

    test "returns 200 with disconnected status", %{conn: conn} do
      # Connection starts as disconnected by default
      conn = get(conn, ~p"/api/connections/self")

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      assert response["status"] == "disconnected"
      assert response["manual_disconnect"] == false
      assert is_nil(response["vpn_ip"])
      assert is_nil(response["vpn_hostname"])
    end

    test "returns 500 when VPN context fails", %{conn: conn} do
      # Clear the connection to simulate context failure
      :ets.delete_all_objects(:vpn_connection)

      conn = get(conn, ~p"/api/connections/self")

      assert json_response(conn, 500)
      response = json_response(conn, 500)
      assert response["error"] == "Failed to retrieve VPN connection status"
    end
  end

  describe "PATCH /api/connections/self" do
    test "updates manual_disconnect to true", %{conn: conn} do
      conn = patch(conn, ~p"/api/connections/self", %{"manual_disconnect" => true})

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      assert response["manual_disconnect"] == true
      assert response["status"] == "disconnected"
    end

    test "updates manual_disconnect to false", %{conn: conn} do
      # First set it to true
      {:ok, _} = VPN.update_connection(%{manual_disconnect: true})

      conn = patch(conn, ~p"/api/connections/self", %{"manual_disconnect" => false})

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      assert response["manual_disconnect"] == false
    end

    test "preserves other connection fields when updating manual_disconnect", %{conn: conn} do
      # Setup existing connection data
      {:ok, _} = VPN.update_connection(%{
        status: :connected,
        vpn_ip: "100.64.0.15",
        vpn_hostname: "edge-admin",
        manual_disconnect: false
      })

      conn = patch(conn, ~p"/api/connections/self", %{"manual_disconnect" => true})

      assert json_response(conn, 200)
      response = json_response(conn, 200)

      # manual_disconnect should be updated
      assert response["manual_disconnect"] == true
      # Other fields should be preserved
      assert response["status"] == "connected"
      assert response["vpn_ip"] == "100.64.0.15"
      assert response["vpn_hostname"] == "edge-admin"
    end

    test "returns 400 for invalid request body", %{conn: conn} do
      conn = patch(conn, ~p"/api/connections/self", %{"invalid_field" => "value"})

      assert json_response(conn, 400)
      response = json_response(conn, 400)

      assert response["error"] == "Invalid request"
      assert response["message"] == "Only 'manual_disconnect' field is allowed for updates and must be a boolean"
    end

    test "returns 400 when manual_disconnect is not a boolean", %{conn: conn} do
      conn = patch(conn, ~p"/api/connections/self", %{"manual_disconnect" => "true"})

      assert json_response(conn, 400)
      response = json_response(conn, 400)

      assert response["error"] == "Invalid request"
      assert response["message"] == "Only 'manual_disconnect' field is allowed for updates and must be a boolean"
    end

    test "returns 400 for empty request body", %{conn: conn} do
      conn = patch(conn, ~p"/api/connections/self", %{})

      assert json_response(conn, 400)
      response = json_response(conn, 400)

      assert response["error"] == "Invalid request"
      assert response["message"] == "Only 'manual_disconnect' field is allowed for updates and must be a boolean"
    end
  end
end
