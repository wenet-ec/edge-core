# tailscale/test/tailscale/workers/auto_reconnecting_worker_test.exs
defmodule Tailscale.Workers.AutoReconnectingWorkerTest do
  use ExUnit.Case
  import Mox
  import Tailscale.Factory

  alias Tailscale.Workers.AutoReconnectingWorker
  alias Tailscale.Cli.MockClient, as: MockCliClient

  setup :verify_on_exit!

  setup do
    # Start ConnectionManager for tests
    start_supervised(Tailscale.ConnectionManager)
    Tailscale.ConnectionManager.reset_connection()
    :ok
  end

  describe "perform/1" do
    test "performs auto-reconnection with valid args" do
      # Set up a disconnected state that should trigger reconnection
      Tailscale.ConnectionManager.create_connection(%{
        status: :disconnected,
        manual_disconnect: false
      })

      MockCliClient
      |> expect(:connect_to_vpn, fn "http://vpn.test", "key123", "test-host" ->
        {:ok, %{vpn_ip: "100.64.0.1", vpn_hostname: "test-host"}}
      end)

      args = %{
        "vpn_url" => "http://vpn.test",
        "enrollment_key" => "key123",
        "hostname_provider" => "test-host"
      }

      result = AutoReconnectingWorker.perform(args)
      assert :ok = result
    end

    test "performs auto-reconnection with atom keys" do
      # Set up a disconnected state that should trigger reconnection
      Tailscale.ConnectionManager.create_connection(%{
        status: :disconnected,
        manual_disconnect: false
      })

      MockCliClient
      |> expect(:connect_to_vpn, fn "http://vpn.test", "key123", "test-host" ->
        {:ok, %{vpn_ip: "100.64.0.1", vpn_hostname: "test-host"}}
      end)

      args = %{
        vpn_url: "http://vpn.test",
        enrollment_key: "key123",
        hostname_provider: "test-host"
      }

      result = AutoReconnectingWorker.perform(args)
      assert :ok = result
    end

    test "returns error when vpn_url is missing" do
      args = %{
        "enrollment_key" => "key123",
        "hostname_provider" => "test-host"
      }

      {:error, reason} = AutoReconnectingWorker.perform(args)
      assert reason == "vpn_url is required"
    end

    test "returns error when enrollment_key is missing" do
      args = %{
        "vpn_url" => "http://vpn.test",
        "hostname_provider" => "test-host"
      }

      {:error, reason} = AutoReconnectingWorker.perform(args)
      assert reason == "enrollment_key is required"
    end

    test "returns error when hostname_provider is missing" do
      args = %{
        "vpn_url" => "http://vpn.test",
        "enrollment_key" => "key123"
      }

      {:error, reason} = AutoReconnectingWorker.perform(args)
      assert reason == "hostname_provider is required"
    end

    test "skips reconnection when conditions not met" do
      # Set up a connected state - should skip reconnection
      Tailscale.ConnectionManager.create_connection(%{
        status: :connected,
        manual_disconnect: false
      })

      args = %{
        "vpn_url" => "http://vpn.test",
        "enrollment_key" => "key123",
        "hostname_provider" => "test-host"
      }

      result = AutoReconnectingWorker.perform(args)
      assert :ok = result
    end
  end

  describe "perform_with_env_config/1" do
    test "uses environment variables" do
      # Set up environment
      System.put_env("VPN_URL", "http://env.vpn.test")
      System.put_env("ENROLLMENT_KEY", "env-key-456")

      # Set up a disconnected state that should trigger reconnection
      Tailscale.ConnectionManager.create_connection(%{
        status: :disconnected,
        manual_disconnect: false
      })

      MockCliClient
      |> expect(:connect_to_vpn, fn "http://env.vpn.test", "env-key-456", "env-host" ->
        {:ok, %{vpn_ip: "100.64.0.2", vpn_hostname: "env-host"}}
      end)

      result = AutoReconnectingWorker.perform_with_env_config("env-host")
      assert :ok = result

      # Clean up environment
      System.delete_env("VPN_URL")
      System.delete_env("ENROLLMENT_KEY")
    end

    test "returns error when environment variables missing" do
      System.delete_env("VPN_URL")
      System.delete_env("ENROLLMENT_KEY")

      {:error, reason} = AutoReconnectingWorker.perform_with_env_config("test-host")
      assert reason == "vpn_url is required"
    end
  end
end