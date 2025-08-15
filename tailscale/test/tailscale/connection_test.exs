# tailscale/test/tailscale/connection_test.exs
defmodule Tailscale.ConnectionTest do
  use ExUnit.Case
  import Tailscale.Factory

  alias Tailscale.Connection

  describe "new/1" do
    test "creates connection with default values" do
      connection = Connection.new()
      
      assert connection.status == :disconnected
      assert connection.manual_disconnect == false
      assert connection.vpn_ip == nil
      assert connection.vpn_hostname == nil
      assert connection.last_error == nil
      assert %DateTime{} = connection.inserted_at
      assert %DateTime{} = connection.updated_at
    end

    test "creates connection with custom attributes" do
      attrs = %{
        status: :connected,
        vpn_ip: "100.64.0.1",
        vpn_hostname: "test-node"
      }
      
      connection = Connection.new(attrs)
      
      assert connection.status == :connected
      assert connection.vpn_ip == "100.64.0.1"
      assert connection.vpn_hostname == "test-node"
    end
  end

  describe "update/2" do
    test "updates connection with valid attributes" do
      connection = build(:connection)
      
      attrs = %{
        status: :connected,
        vpn_ip: "100.64.0.1",
        vpn_hostname: "updated-node"
      }
      
      {:ok, updated_connection} = Connection.update(connection, attrs)
      
      assert updated_connection.status == :connected
      assert updated_connection.vpn_ip == "100.64.0.1"
      assert updated_connection.vpn_hostname == "updated-node"
      assert updated_connection.updated_at != connection.updated_at
    end

    test "returns error for invalid status" do
      connection = build(:connection)
      
      {:error, reason} = Connection.update(connection, %{status: :invalid_status})
      
      assert reason == "Invalid status: :invalid_status"
    end

    test "returns error for invalid manual_disconnect" do
      connection = build(:connection)
      
      {:error, reason} = Connection.update(connection, %{manual_disconnect: "not_boolean"})
      
      assert reason == "manual_disconnect must be boolean, got: \"not_boolean\""
    end
  end

  describe "validate/1" do
    test "validates valid connection" do
      connection = build(:connection)
      
      {:ok, validated_connection} = Connection.validate(connection)
      
      assert validated_connection == connection
    end

    test "returns error for invalid connection struct" do
      {:error, reason} = Connection.validate(%{invalid: :struct})
      
      assert String.contains?(reason, "Invalid connection struct:")
    end

    test "validates status values" do
      valid_statuses = [:connected, :disconnected, :connecting]
      
      Enum.each(valid_statuses, fn status ->
        connection = build(:connection, status: status)
        {:ok, _} = Connection.validate(connection)
      end)
    end
  end
end