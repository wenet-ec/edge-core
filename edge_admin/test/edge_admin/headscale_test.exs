# edge_admin/test/edge_admin/headscale_test.exs
defmodule EdgeAdmin.HeadscaleTest do
  use EdgeAdmin.DataCase

  import Mox

  alias EdgeAdmin.Headscale

  # Mock for the Headscale client
  defmock(EdgeAdmin.Headscale.ClientMock, for: EdgeAdmin.Headscale.Behaviour)

  setup do
    # Configure the mock client for tests
    Application.put_env(:edge_admin, :headscale_client, EdgeAdmin.Headscale.ClientMock)

    on_exit(fn ->
      # Restore the original client
      Application.put_env(:edge_admin, :headscale_client, EdgeAdmin.Headscale.Client)
    end)

    :ok
  end

  describe "node operations" do
    test "get_node_by_hostname/1 success and error cases" do
      expected_result = %{
        vpn_ip: "100.64.0.1",
        vpn_hostname: "node-abc123",
        online: true,
        last_seen: "2024-01-01T12:00:00Z"
      }

      EdgeAdmin.Headscale.ClientMock
      |> expect(:get_node_by_hostname, fn "node-abc123" ->
        {:ok, expected_result}
      end)
      |> expect(:get_node_by_hostname, fn "nonexistent" ->
        {:error, :node_not_found}
      end)

      # Success case
      assert {:ok, result} = Headscale.get_node_by_hostname("node-abc123")
      assert result == expected_result

      # Error case
      assert {:error, :node_not_found} = Headscale.get_node_by_hostname("nonexistent")
    end

    test "list_nodes_for_user/1 returns node list" do
      expected_result = [
        %{vpn_ip: "100.64.0.1", vpn_hostname: "node-1", online: true},
        %{vpn_ip: "100.64.0.2", vpn_hostname: "node-2", online: false}
      ]

      EdgeAdmin.Headscale.ClientMock
      |> expect(:list_nodes_for_user, fn "edge-nodes" ->
        {:ok, expected_result}
      end)

      assert {:ok, result} = Headscale.list_nodes_for_user()
      assert result == expected_result
    end
  end

  describe "enrollment key operations" do
    test "create_enrollment_key with default and custom users" do
      expected_result = %{
        key: "preauth-key-abc123",
        expiration: "2024-06-10T15:30:00Z",
        created_at: "2024-06-10T14:30:00Z"
      }

      EdgeAdmin.Headscale.ClientMock
      |> expect(:create_enrollment_key, fn "edge-nodes" ->
        {:ok, expected_result}
      end)
      |> expect(:create_enrollment_key, fn "custom-user" ->
        {:ok, expected_result}
      end)
      |> expect(:create_enrollment_key, fn "edge-nodes" ->
        {:error, :vpn_service_unavailable}
      end)

      # Default user (no argument)
      assert {:ok, result} = Headscale.create_enrollment_key()
      assert result == expected_result

      # Custom user
      assert {:ok, result} = Headscale.create_enrollment_key("custom-user")
      assert result == expected_result

      # Error case
      assert {:error, :vpn_service_unavailable} = Headscale.create_enrollment_key()
    end
  end

  describe "user operations" do
    test "get_user/1 success and error cases" do
      expected_result = %{id: "user123", name: "edge-nodes"}

      EdgeAdmin.Headscale.ClientMock
      |> expect(:get_user, fn "edge-nodes" ->
        {:ok, expected_result}
      end)
      |> expect(:get_user, fn "nonexistent" ->
        {:error, :user_not_found}
      end)

      # Success case
      assert {:ok, result} = Headscale.get_user("edge-nodes")
      assert result == expected_result

      # Error case
      assert {:error, :user_not_found} = Headscale.get_user("nonexistent")
    end
  end
end
