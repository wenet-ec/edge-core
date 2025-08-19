# edge_admin/test/edge_admin/vpn_test.exs
defmodule EdgeAdmin.VPNTest do
  use EdgeAdmin.DataCase, async: true

  import Mox

  alias EdgeAdmin.TailscaleMock
  alias EdgeAdmin.VPN
  alias EdgeAdmin.VPN.Connection

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  describe "basic VPN operations (delegated functions)" do
    test "connect_to_vpn/3 delegates to Tailscale module" do
      expect(TailscaleMock, :connect_to_vpn, fn "http://test-vpn:8080", "test-key", "edge-admin" ->
        {:ok, %{status: :connected, message: "Connected successfully"}}
      end)

      assert {:ok, %{status: :connected}} = VPN.connect_to_vpn("http://test-vpn:8080", "test-key", "edge-admin")
    end

    test "disconnect_from_vpn/0 delegates to Tailscale module" do
      expect(TailscaleMock, :disconnect_from_vpn, fn ->
        {:ok, %{status: :disconnected}}
      end)

      assert {:ok, %{status: :disconnected}} = VPN.disconnect_from_vpn()
    end

    test "get_connection/0 delegates to Tailscale module" do
      connection = build(:tailscale_connection)

      expect(TailscaleMock, :get_connection, fn ->
        {:ok, connection}
      end)

      assert {:ok, ^connection} = VPN.get_connection()
    end

    test "create_enrollment_key/1 delegates to Tailscale module" do
      enrollment_data = build(:enrollment_key)

      expect(TailscaleMock, :create_enrollment_key, fn "edge-nodes" ->
        {:ok, enrollment_data}
      end)

      assert {:ok, ^enrollment_data} = VPN.create_enrollment_key("edge-nodes")
    end
  end

  describe "update_connection/1" do
    test "successfully updates connection with valid attributes" do
      connection = build(:tailscale_connection)
      updated_connection = %{connection | status: :connected, vpn_ip: "100.64.0.10"}

      expect(TailscaleMock, :get_connection!, fn ->
        connection
      end)

      expect(TailscaleMock, :update_connection, fn ^connection, %{status: :connected} ->
        {:ok, updated_connection}
      end)

      assert {:ok, ^updated_connection} = VPN.update_connection(%{status: :connected})
    end

    test "handles errors from get_connection!" do
      expect(TailscaleMock, :get_connection!, fn ->
        raise "Connection not found"
      end)

      assert_raise RuntimeError, "Connection not found", fn ->
        VPN.update_connection(%{status: :connected})
      end
    end
  end

  describe "update_connection_from_params/1" do
    test "successfully updates with valid manual_disconnect: true" do
      connection = build(:tailscale_connection)
      disconnected_connection = %{connection | manual_disconnect: true, status: :disconnected}

      expect(TailscaleMock, :get_connection, fn ->
        {:ok, connection}
      end)

      expect(TailscaleMock, :disconnect_from_vpn_manual, fn ->
        {:ok, disconnected_connection}
      end)

      params = %{"manual_disconnect" => true}
      assert {:ok, result} = VPN.update_connection_from_params(params)
      assert result.manual_disconnect == true
    end

    test "successfully updates with valid manual_disconnect: false" do
      connection = build(:tailscale_connection, %{manual_disconnect: true})
      updated_connection = %{connection | manual_disconnect: false}

      expect(TailscaleMock, :get_connection, fn ->
        {:ok, connection}
      end)

      expect(TailscaleMock, :get_connection!, fn ->
        connection
      end)

      expect(TailscaleMock, :update_connection, fn ^connection, %{manual_disconnect: false} ->
        {:ok, updated_connection}
      end)

      params = %{"manual_disconnect" => false}
      assert {:ok, result} = VPN.update_connection_from_params(params)
      assert result.manual_disconnect == false
    end

    test "returns unchanged connection when manual_disconnect is nil" do
      connection = build(:tailscale_connection)

      expect(TailscaleMock, :get_connection, fn ->
        {:ok, connection}
      end)

      params = %{}
      assert {:ok, result} = VPN.update_connection_from_params(params)
      assert %Connection{} = result
    end

    test "returns error for invalid parameters" do
      connection = build(:tailscale_connection)

      expect(TailscaleMock, :get_connection, fn ->
        {:ok, connection}
      end)

      # Invalid type for manual_disconnect
      params = %{"manual_disconnect" => "invalid"}
      assert {:error, %Ecto.Changeset{} = changeset} = VPN.update_connection_from_params(params)
      assert changeset.valid? == false
      assert Keyword.has_key?(changeset.errors, :manual_disconnect)
    end

    test "handles connection retrieval errors" do
      expect(TailscaleMock, :get_connection, fn ->
        {:error, :not_found}
      end)

      params = %{"manual_disconnect" => true}
      assert {:error, :not_found} = VPN.update_connection_from_params(params)
    end
  end

  describe "update_connection_manual_disconnect/1" do
    test "performs manual disconnect when true" do
      disconnected_connection = build(:tailscale_connection, %{manual_disconnect: true, status: :disconnected})

      expect(TailscaleMock, :disconnect_from_vpn_manual, fn ->
        {:ok, disconnected_connection}
      end)

      assert {:ok, result} = VPN.update_connection_manual_disconnect(true)
      assert result.manual_disconnect == true
      assert result.status == :disconnected
    end

    test "re-enables auto-reconnection when false" do
      connection = build(:tailscale_connection, %{manual_disconnect: false})

      expect(TailscaleMock, :update_connection, fn _, %{manual_disconnect: false} ->
        {:ok, connection}
      end)

      expect(TailscaleMock, :get_connection!, fn ->
        build(:tailscale_connection, %{manual_disconnect: true})
      end)

      assert {:ok, result} = VPN.update_connection_manual_disconnect(false)
      assert result.manual_disconnect == false
    end
  end

  describe "attempt_auto_reconnection/0" do
    test "attempts reconnection with EdgeAdmin configuration" do
      expect(TailscaleMock, :attempt_auto_reconnection, fn
        "http://test-vpn:8080", "test-key", "edge-admin" ->
          {:ok, %{status: :reconnected, message: "Auto-reconnection successful"}}
      end)

      assert {:ok, %{status: :reconnected}} = VPN.attempt_auto_reconnection()
    end

    test "handles reconnection failures" do
      expect(TailscaleMock, :attempt_auto_reconnection, fn _, _, _ ->
        {:error, :auto_reconnection_failed}
      end)

      assert {:error, :auto_reconnection_failed} = VPN.attempt_auto_reconnection()
    end
  end

  describe "connect_to_vpn_manual/0" do
    test "connects manually with EdgeAdmin configuration" do
      connected_connection = build(:connected_tailscale_connection)

      expect(TailscaleMock, :connect_to_vpn_manual, fn
        "http://test-vpn:8080", "test-key", "edge-admin" ->
          {:ok, connected_connection}
      end)

      assert {:ok, result} = VPN.connect_to_vpn_manual()
      assert result.status == :connected
      assert result.vpn_ip == "100.64.0.10"
    end
  end

  describe "create_enrollment_key_with_error_handling/0" do
    test "returns enrollment data on success" do
      enrollment_data = build(:enrollment_key)

      expect(TailscaleMock, :create_enrollment_key, fn "edge-nodes" ->
        {:ok, enrollment_data}
      end)

      assert {:ok, ^enrollment_data} = VPN.create_enrollment_key_with_error_handling()
    end

    test "handles VPN service unavailable error" do
      expect(TailscaleMock, :create_enrollment_key, fn "edge-nodes" ->
        {:error, :vpn_service_unavailable}
      end)

      assert {:error, :vpn_service_unavailable, "VPN service is currently unavailable"} =
               VPN.create_enrollment_key_with_error_handling()
    end

    test "handles user not found error" do
      expect(TailscaleMock, :create_enrollment_key, fn "edge-nodes" ->
        {:error, :user_not_found}
      end)

      assert {:error, :internal_server_error, "edge-nodes user not found in VPN system"} =
               VPN.create_enrollment_key_with_error_handling()
    end

    test "handles other errors" do
      expect(TailscaleMock, :create_enrollment_key, fn "edge-nodes" ->
        {:error, :unknown_error}
      end)

      assert {:error, :unknown_error} = VPN.create_enrollment_key_with_error_handling()
    end
  end

  describe "get_connection_as_embedded/0" do
    test "transforms Tailscale connection to EdgeAdmin connection" do
      tailscale_conn = build(:connected_tailscale_connection)

      expect(TailscaleMock, :get_connection, fn ->
        {:ok, tailscale_conn}
      end)

      assert {:ok, %Connection{} = edge_conn} = VPN.get_connection_as_embedded()
      assert edge_conn.status == tailscale_conn.status
      assert edge_conn.vpn_ip == tailscale_conn.vpn_ip
      assert edge_conn.vpn_hostname == tailscale_conn.vpn_hostname
    end

    test "propagates connection errors" do
      expect(TailscaleMock, :get_connection, fn ->
        {:error, :not_found}
      end)

      assert {:error, :not_found} = VPN.get_connection_as_embedded()
    end
  end

  describe "environment configuration" do
    test "uses Application environment for VPN URL and enrollment key" do
      # VPN URL and enrollment key are set in test_helper.exs
      expect(TailscaleMock, :attempt_auto_reconnection, fn
        "http://test-vpn:8080", "test-key", "edge-admin" ->
          {:ok, %{status: :reconnected}}
      end)

      assert {:ok, %{status: :reconnected}} = VPN.attempt_auto_reconnection()
    end
  end

  describe "error scenarios" do
    test "handles missing environment variables gracefully in tests" do
      # Temporarily remove config and system env vars
      original_vpn_url = (fn -> Application.get_env(:edge_admin, :vpn_url) end).()
      original_enrollment_key = (fn -> Application.get_env(:edge_admin, :enrollment_key) end).()
      original_sys_vpn_url = (fn -> System.get_env("VPN_URL") end).()
      original_sys_enrollment_key = (fn -> System.get_env("ENROLLMENT_KEY") end).()

      Application.delete_env(:edge_admin, :vpn_url)
      Application.delete_env(:edge_admin, :enrollment_key)
      System.delete_env("VPN_URL")
      System.delete_env("ENROLLMENT_KEY")

      try do
        assert_raise RuntimeError, ~r/VPN_URL environment variable not set/, fn ->
          VPN.attempt_auto_reconnection()
        end
      after
        # Restore config
        if original_vpn_url, do: Application.put_env(:edge_admin, :vpn_url, original_vpn_url)
        if original_enrollment_key, do: Application.put_env(:edge_admin, :enrollment_key, original_enrollment_key)
        if original_sys_vpn_url, do: System.put_env("VPN_URL", original_sys_vpn_url)
        if original_sys_enrollment_key, do: System.put_env("ENROLLMENT_KEY", original_sys_enrollment_key)
      end
    end
  end
end
