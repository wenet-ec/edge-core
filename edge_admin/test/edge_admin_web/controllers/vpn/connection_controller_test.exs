# edge_admin/test/edge_admin_web/controllers/vpn/connection_controller_test.exs
defmodule EdgeAdminWeb.VPN.ConnectionControllerTest do
  use EdgeAdminWeb.ConnCase, async: true

  import Mox
  alias EdgeAdmin.TailscaleMock

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  describe "GET /api/connections/self" do
    test "returns disconnected connection status", %{conn: conn} do
      disconnected_connection = build(:tailscale_connection)
      
      expect(TailscaleMock, :get_connection, fn ->
        {:ok, disconnected_connection}
      end)

      conn = get(conn, ~p"/api/connections/self")
      response = json_response(conn, 200)
      data = response["data"]

      assert data["status"] == "disconnected"
      assert data["manual_disconnect"] == false
      assert is_nil(data["vpn_ip"])
      assert is_nil(data["vpn_hostname"])
      assert is_binary(data["inserted_at"])
      assert is_binary(data["updated_at"])
    end

    test "returns connected connection status", %{conn: conn} do
      connected_connection = build(:connected_tailscale_connection)
      
      expect(TailscaleMock, :get_connection, fn ->
        {:ok, connected_connection}
      end)

      conn = get(conn, ~p"/api/connections/self")
      response = json_response(conn, 200)
      data = response["data"]

      assert data["status"] == "connected"
      assert data["vpn_ip"] == "100.64.0.10"
      assert data["vpn_hostname"] == "edge-admin"
      assert data["manual_disconnect"] == false
    end

    test "returns connection with all timestamp fields", %{conn: conn} do
      now = DateTime.utc_now()
      connection = build(:connected_tailscale_connection, %{
        connected_at: now,
        last_checked_at: now,
        inserted_at: now,
        updated_at: now
      })
      
      expect(TailscaleMock, :get_connection, fn ->
        {:ok, connection}
      end)

      conn = get(conn, ~p"/api/connections/self")
      response = json_response(conn, 200)
      data = response["data"]

      assert is_binary(data["connected_at"])
      assert is_binary(data["last_checked_at"])
      assert is_binary(data["inserted_at"])
      assert is_binary(data["updated_at"])
      
      # Verify timestamps are valid ISO8601
      assert {:ok, _, _} = DateTime.from_iso8601(data["connected_at"])
      assert {:ok, _, _} = DateTime.from_iso8601(data["last_checked_at"])
      assert {:ok, _, _} = DateTime.from_iso8601(data["inserted_at"])
      assert {:ok, _, _} = DateTime.from_iso8601(data["updated_at"])
    end

    test "handles connection retrieval errors", %{conn: conn} do
      expect(TailscaleMock, :get_connection, fn ->
        {:error, :not_found}
      end)

      conn = get(conn, ~p"/api/connections/self")
      response = json_response(conn, 500)

      assert response["error"] == "Failed to retrieve VPN connection status"
    end

    test "handles unexpected connection retrieval errors", %{conn: conn} do
      expect(TailscaleMock, :get_connection, fn ->
        {:error, :unexpected_error}
      end)

      conn = get(conn, ~p"/api/connections/self")
      response = json_response(conn, 500)

      assert response["error"] == "Failed to retrieve VPN connection status"
      assert String.contains?(response["details"], "unexpected_error")
    end
  end

  describe "PATCH /api/connections/self" do
    test "successfully updates manual_disconnect to true (performs disconnect)", %{conn: conn} do
      original_connection = build(:connected_tailscale_connection)
      disconnected_connection = build(:tailscale_connection, %{
        manual_disconnect: true,
        status: :disconnected,
        vpn_ip: nil,
        vpn_hostname: nil,
        connected_at: nil
      })
      
      expect(TailscaleMock, :get_connection, fn ->
        {:ok, original_connection}
      end)
      
      expect(TailscaleMock, :disconnect_from_vpn_manual, fn ->
        {:ok, disconnected_connection}
      end)

      conn = patch(conn, ~p"/api/connections/self", %{"manual_disconnect" => true})
      response = json_response(conn, 200)
      data = response["data"]

      assert data["manual_disconnect"] == true
      assert data["status"] == "disconnected"
      assert is_nil(data["vpn_ip"])
    end

    test "successfully updates manual_disconnect to false (re-enables auto-reconnection)", %{conn: conn} do
      original_connection = build(:tailscale_connection, %{manual_disconnect: true})
      updated_connection = build(:tailscale_connection, %{manual_disconnect: false})
      
      expect(TailscaleMock, :get_connection, fn ->
        {:ok, original_connection}
      end)
      
      expect(TailscaleMock, :get_connection!, fn ->
        original_connection
      end)
      
      expect(TailscaleMock, :update_connection, fn ^original_connection, %{manual_disconnect: false} ->
        {:ok, updated_connection}
      end)

      conn = patch(conn, ~p"/api/connections/self", %{"manual_disconnect" => false})
      response = json_response(conn, 200)
      data = response["data"]

      assert data["manual_disconnect"] == false
    end

    test "preserves other connection fields during update", %{conn: conn} do
      connected_connection = build(:connected_tailscale_connection, %{
        vpn_ip: "100.64.0.15",
        vpn_hostname: "edge-admin"
      })
      disconnected_connection = %{connected_connection | 
        manual_disconnect: true,
        status: :disconnected,
        vpn_ip: nil,
        connected_at: nil
      }
      
      expect(TailscaleMock, :get_connection, fn ->
        {:ok, connected_connection}
      end)
      
      expect(TailscaleMock, :disconnect_from_vpn_manual, fn ->
        {:ok, disconnected_connection}
      end)

      conn = patch(conn, ~p"/api/connections/self", %{"manual_disconnect" => true})
      response = json_response(conn, 200)
      data = response["data"]

      assert data["manual_disconnect"] == true
      # These fields should change due to disconnect
      assert data["status"] == "disconnected"
      assert is_nil(data["vpn_ip"])
    end

    test "handles empty params without changes", %{conn: conn} do
      connection = build(:tailscale_connection)
      
      expect(TailscaleMock, :get_connection, fn ->
        {:ok, connection}
      end)

      # Empty params should succeed and return unchanged connection
      conn = patch(conn, ~p"/api/connections/self", %{})
      response = json_response(conn, 200)

      assert response["data"]["manual_disconnect"] == false
      assert response["data"]["status"] == "disconnected"
    end

    test "validates manual_disconnect field type", %{conn: conn} do
      connection = build(:tailscale_connection)
      
      # Test genuinely invalid values that Ecto won't cast
      invalid_values = [
        "invalid",  # invalid string
        %{},        # object
        [],         # array
        1.5         # float
      ]

      for invalid_value <- invalid_values do
        expect(TailscaleMock, :get_connection, fn ->
          {:ok, connection}
        end)
        
        conn = patch(conn, ~p"/api/connections/self", %{"manual_disconnect" => invalid_value})
        response = json_response(conn, 422)

        assert response["errors"]
        assert Map.has_key?(response["errors"], "manual_disconnect")
      end
    end

    test "ignores unknown fields in request", %{conn: conn} do
      original_connection = build(:tailscale_connection, %{manual_disconnect: true})
      updated_connection = build(:tailscale_connection, %{manual_disconnect: false})
      
      expect(TailscaleMock, :get_connection, fn ->
        {:ok, original_connection}
      end)
      
      expect(TailscaleMock, :get_connection!, fn ->
        original_connection
      end)
      
      expect(TailscaleMock, :update_connection, fn _, %{manual_disconnect: false} ->
        {:ok, updated_connection}
      end)

      # Include valid and invalid fields
      params = %{
        "manual_disconnect" => false,
        "invalid_field" => "should_be_ignored",
        "status" => "connected",  # Should be ignored in update
        "vpn_ip" => "1.2.3.4"     # Should be ignored in update
      }

      conn = patch(conn, ~p"/api/connections/self", params)
      response = json_response(conn, 200)

      # Should succeed and only process manual_disconnect
      assert response["data"]["manual_disconnect"] == false
    end

    test "handles connection retrieval errors", %{conn: conn} do
      expect(TailscaleMock, :get_connection, fn ->
        {:error, :not_found}
      end)

      conn = patch(conn, ~p"/api/connections/self", %{"manual_disconnect" => true})
      response = json_response(conn, 422)

      assert response["error"] == "Failed to update VPN connection"
      assert String.contains?(response["details"], "not_found")
    end

    test "handles disconnect operation errors", %{conn: conn} do
      original_connection = build(:connected_tailscale_connection)
      
      expect(TailscaleMock, :get_connection, fn ->
        {:ok, original_connection}
      end)
      
      expect(TailscaleMock, :disconnect_from_vpn_manual, fn ->
        {:error, :disconnect_failed}
      end)

      conn = patch(conn, ~p"/api/connections/self", %{"manual_disconnect" => true})
      response = json_response(conn, 422)

      assert response["error"] == "Failed to update VPN connection"
      assert String.contains?(response["details"], "disconnect_failed")
    end

    test "handles update operation errors", %{conn: conn} do
      original_connection = build(:tailscale_connection, %{manual_disconnect: true})
      
      expect(TailscaleMock, :get_connection, fn ->
        {:ok, original_connection}
      end)
      
      expect(TailscaleMock, :get_connection!, fn ->
        original_connection
      end)
      
      expect(TailscaleMock, :update_connection, fn _, _ ->
        {:error, :update_failed}
      end)

      conn = patch(conn, ~p"/api/connections/self", %{"manual_disconnect" => false})
      response = json_response(conn, 422)

      assert response["error"] == "Failed to update VPN connection"
      assert String.contains?(response["details"], "update_failed")
    end
  end

  describe "API response format" do
    test "follows consistent JSON:API-like structure", %{conn: conn} do
      connection = build(:connected_tailscale_connection)
      
      expect(TailscaleMock, :get_connection, fn ->
        {:ok, connection}
      end)

      conn = get(conn, ~p"/api/connections/self")
      response = json_response(conn, 200)

      # Should have data wrapper
      assert Map.has_key?(response, "data")
      data = response["data"]

      # Should have all expected fields
      expected_fields = [
        "status", "vpn_ip", "vpn_hostname", "connected_at", 
        "last_checked_at", "last_error", "last_error_at", 
        "manual_disconnect", "inserted_at", "updated_at"
      ]
      
      for field <- expected_fields do
        assert Map.has_key?(data, field), "Missing field: #{field}"
      end
    end
  end
end
