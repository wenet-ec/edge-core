# edge_admin/test/support/factory.ex
defmodule EdgeAdmin.Factory do
  @moduledoc """
  Test data factories for EdgeAdmin.

  This module provides factory functions for creating test data.
  Use `build/2` for structs and `insert/2` for database records.
  """

  use ExMachina.Ecto, repo: EdgeAdmin.Repo

  alias EdgeAdmin.VPN.Connection

  # Keep the existing name factory but make it more useful
  def name_factory do
    Faker.Person.name()
  end

  # Add more useful factories for API testing
  def email_factory do
    Faker.Internet.email()
  end

  def uuid_factory do
    Ecto.UUID.generate()
  end

  # VPN Connection factories
  def tailscale_connection_factory do
    now = DateTime.utc_now()

    %Tailscale.Connection{
      status: :disconnected,
      vpn_ip: nil,
      vpn_hostname: nil,
      connected_at: nil,
      last_checked_at: now,
      last_error: nil,
      last_error_at: nil,
      manual_disconnect: false,
      inserted_at: now,
      updated_at: now
    }
  end

  def connected_tailscale_connection_factory do
    now = DateTime.utc_now()

    %Tailscale.Connection{
      status: :connected,
      vpn_ip: "100.64.0.10",
      vpn_hostname: "edge-admin",
      connected_at: now,
      last_checked_at: now,
      last_error: nil,
      last_error_at: nil,
      manual_disconnect: false,
      inserted_at: now,
      updated_at: now
    }
  end

  def edge_admin_vpn_connection_factory do
    tailscale_conn = build(:tailscale_connection)
    Connection.from_tailscale_connection(tailscale_conn)
  end

  def connected_edge_admin_vpn_connection_factory do
    tailscale_conn = build(:connected_tailscale_connection)
    Connection.from_tailscale_connection(tailscale_conn)
  end

  # VPN API response factories
  def vpn_status_response_factory do
    %{
      "BackendState" => "Running",
      "TailscaleIPs" => ["100.64.0.10"]
    }
  end

  def vpn_node_factory do
    %{
      id: "test-node-#{sequence(:node_id, & &1)}",
      name: "node-#{sequence(:node_name, & &1)}",
      ips: ["100.64.0.#{sequence(:ip_suffix, &(&1 + 10))}"]
    }
  end

  def enrollment_key_factory do
    %{
      key: "nodekey:test-enrollment-key-#{sequence(:key_id, & &1)}",
      expiration: DateTime.add(DateTime.utc_now(), 3600, :second),
      created_at: DateTime.utc_now()
    }
  end

  # API request factories for testing
  def api_request_params_factory do
    %{
      "data" => %{
        "type" => "test",
        "attributes" => %{
          "name" => Faker.Person.name(),
          "email" => Faker.Internet.email()
        }
      }
    }
  end

  def json_response_factory do
    %{
      "data" => %{
        "id" => Ecto.UUID.generate(),
        "type" => "test",
        "attributes" => build(:api_request_params)["data"]["attributes"]
      }
    }
  end
end
