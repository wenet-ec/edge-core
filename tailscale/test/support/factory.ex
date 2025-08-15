# tailscale/test/support/factory.ex
defmodule Tailscale.Factory do
  @moduledoc """
  Factory for creating test data.
  """

  use ExMachina

  def connection_factory do
    %Tailscale.Connection{
      status: :disconnected,
      vpn_ip: nil,
      vpn_hostname: nil,
      connected_at: nil,
      last_checked_at: DateTime.utc_now(),
      last_error: nil,
      last_error_at: nil,
      manual_disconnect: false,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  def connection_connected_factory do
    build(:connection, %{
      status: :connected,
      vpn_ip: "100.64.0.1",
      vpn_hostname: "test-node",
      connected_at: DateTime.utc_now()
    })
  end

  def connection_connecting_factory do
    build(:connection, %{
      status: :connecting
    })
  end

  def tailscale_status_factory do
    %{
      "BackendState" => "Running",
      "Self" => %{
        "Online" => true,
        "HostName" => "test-node",
        "TailscaleIPs" => ["100.64.0.1"]
      }
    }
  end

  def tailscale_status_offline_factory do
    %{
      "BackendState" => "Stopped",
      "Self" => %{
        "Online" => false,
        "HostName" => "test-node",
        "TailscaleIPs" => []
      }
    }
  end

  def vpn_node_factory do
    %{
      "name" => "test-node",
      "ipAddresses" => ["100.64.0.1"],
      "online" => true,
      "lastSeen" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def enrollment_key_factory do
    %{
      "key" => "enrollment-key-12345",
      "expiration" => DateTime.utc_now() |> DateTime.add(1, :hour) |> DateTime.to_iso8601(),
      "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end