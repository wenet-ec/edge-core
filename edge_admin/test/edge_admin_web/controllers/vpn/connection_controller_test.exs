# edge_admin/test/edge_admin_web/controllers/vpn/connection_controller_test.exs
defmodule EdgeAdminWeb.VPN.ConnectionControllerTest do
  use EdgeAdminWeb.ConnCase, async: false

  alias EdgeAdmin.Tailscale

  setup do
    # Reset the ETS table state between tests
    :ets.delete_all_objects(:tailscale_connection)
    {:ok, _} = Tailscale.create_connection(%{})
    :ok
  end

  describe "GET /api/connections/self" do
    test "returns connection status", %{conn: conn} do
      # Test default disconnected state
      conn = get(conn, ~p"/api/connections/self")
      response = json_response(conn, 200)
      data = response["data"]

      assert data["status"] == "disconnected"
      assert data["manual_disconnect"] == false
      assert is_nil(data["vpn_ip"])

      # Test connected state
      {:ok, _} =
        Tailscale.update_connection(%{
          status: :connected,
          vpn_ip: "100.64.0.10",
          vpn_hostname: "edge-admin"
        })

      conn = get(conn, ~p"/api/connections/self")
      response = json_response(conn, 200)
      data = response["data"]

      assert data["status"] == "connected"
      assert data["vpn_ip"] == "100.64.0.10"
      assert data["vpn_hostname"] == "edge-admin"
    end

    test "returns connection with timestamps", %{conn: conn} do
      conn = get(conn, ~p"/api/connections/self")
      response = json_response(conn, 200)
      data = response["data"]

      assert data["status"] == "disconnected"
      assert data["manual_disconnect"] == false
      assert is_binary(data["inserted_at"])
      assert is_binary(data["updated_at"])
      assert {:ok, _, _} = DateTime.from_iso8601(data["inserted_at"])
      assert {:ok, _, _} = DateTime.from_iso8601(data["updated_at"])
    end
  end

  describe "PATCH /api/connections/self" do
    test "updates manual_disconnect flag", %{conn: conn} do
      # Test setting to true
      conn = patch(conn, ~p"/api/connections/self", %{"manual_disconnect" => true})
      response = json_response(conn, 200)
      data = response["data"]

      assert data["manual_disconnect"] == true

      # Test setting to false
      conn = patch(conn, ~p"/api/connections/self", %{"manual_disconnect" => false})
      response = json_response(conn, 200)
      data = response["data"]

      assert data["manual_disconnect"] == false
    end

    test "preserves other connection fields", %{conn: conn} do
      {:ok, _} =
        Tailscale.update_connection(%{
          status: :connected,
          vpn_ip: "100.64.0.15",
          vpn_hostname: "edge-admin"
        })

      conn = patch(conn, ~p"/api/connections/self", %{"manual_disconnect" => true})
      response = json_response(conn, 200)
      data = response["data"]

      assert data["manual_disconnect"] == true
      assert data["status"] == "connected"
      assert data["vpn_ip"] == "100.64.0.15"
      assert data["vpn_hostname"] == "edge-admin"
    end

    test "validates request parameters", %{conn: conn} do
      invalid_requests = [
        %{"invalid_field" => "value"},
        # string instead of boolean
        %{"manual_disconnect" => "true"},
        # empty body
        %{}
      ]

      for invalid_body <- invalid_requests do
        conn = patch(conn, ~p"/api/connections/self", invalid_body)
        response = json_response(conn, 400)

        assert response["error"] == "Invalid request"
        assert String.contains?(response["message"], "manual_disconnect")
      end
    end
  end
end
