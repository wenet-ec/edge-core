# edge_agent/test/edge_agent/admin_gateway/client_test.exs
defmodule EdgeAgent.AdminGateway.ClientTest do
  use EdgeAgent.DataCase, async: false

  alias EdgeAgent.AdminGateway.Client
  alias EdgeAgent.AdminGateway.Transport
  alias EdgeAgent.Settings
  # urls_to_try/2 — fallback URL priority logic
  #
  # URL ordering is pure and belongs to AdminGateway.Transport. The surrounding
  # Client cases retain coverage for Settings-backed failover behavior.

  describe "urls_to_try/2 — VPN admin URLs take priority" do
    setup do
      Settings.set_api_token("test-token")

      on_exit(fn ->
        Settings.set_admin_urls([])
        Settings.set_admin_fallback_urls([])
      end)
    end

    test "VPN admin URLs are used when present — returns network error (not :no_admin_urls)" do
      Settings.set_admin_urls(["http://127.0.0.1:1"])
      Settings.set_admin_fallback_urls([])

      # Should try the VPN URL and fail with a network error, NOT :no_admin_urls
      result = Client.list_pending_command_executions()
      assert result != {:error, :no_admin_urls}
      assert match?({:error, _}, result)
    end

    test "public fallback URLs follow all VPN URLs, so one request can recover from VPN transport failures" do
      assert Transport.urls_to_try(
               ["http://100.64.0.4:44000", "http://100.64.0.5:44000"],
               ["https://admin.example.com", "https://admin-backup.example.com"]
             ) == [
               "http://100.64.0.4:44000",
               "http://100.64.0.5:44000",
               "https://admin.example.com",
               "https://admin-backup.example.com"
             ]
    end

    test "duplicate public URL is attempted only once" do
      assert Transport.urls_to_try(
               ["http://100.64.0.4:44000"],
               ["http://100.64.0.4:44000", "https://admin.example.com"]
             ) == ["http://100.64.0.4:44000", "https://admin.example.com"]
    end

    test "when no VPN URLs and no fallback configured → :no_admin_urls" do
      Settings.set_admin_urls([])
      Settings.set_admin_fallback_urls([])

      assert {:error, :no_admin_urls} = Client.register_node(%{node_id: "test"})
    end
  end

  describe "get_urls_to_try/0 — Settings fallback URLs (admin_fallback_urls)" do
    setup do
      on_exit(fn ->
        Settings.set_admin_urls([])
        Settings.set_admin_fallback_urls([])
      end)
    end

    test "Settings fallback URLs used when VPN empty — returns network error (not :no_admin_urls)" do
      Settings.set_admin_urls([])
      Settings.set_admin_fallback_urls(["http://127.0.0.1:1"])
      Settings.set_api_token("test-token")

      result = Client.list_pending_command_executions()
      assert result != {:error, :no_admin_urls}
      assert match?({:error, _}, result)
    end
  end

  describe "get_urls_to_try/0 — no URLs available" do
    setup do
      Settings.set_api_token("test-token")

      on_exit(fn ->
        Settings.set_admin_urls([])
        Settings.set_admin_fallback_urls([])
      end)
    end

    test "no VPN, no Settings fallback → :no_admin_urls (unauthenticated path)" do
      Settings.set_admin_urls([])
      Settings.set_admin_fallback_urls([])

      assert {:error, :no_admin_urls} = Client.register_node(%{node_id: "test"})
    end

    test "no VPN, no Settings fallback → :no_admin_urls (authenticated re-registration path)" do
      Settings.set_admin_urls([])
      Settings.set_admin_fallback_urls([])

      assert {:error, :no_admin_urls} = Client.reregister_node(%{})
    end
  end

  # verify_enrollment_key/2 — payload shape and fallback behaviour
  #
  # The function makes real HTTP calls. We can't easily mock Req here without
  # a bypass library. Instead we verify:
  # - All URLs fail → {:error, {:all_requests_failed, _}}
  # - Single bad URL → network failure, tried once

  describe "verify_enrollment_key/2" do
    test "empty admin_urls list → {:error, {:all_requests_failed, _}}" do
      result = Client.verify_enrollment_key("some-blob==", [])
      assert {:error, {:all_requests_failed, reason}} = result
      assert is_binary(reason)
    end

    test "single unreachable URL → {:error, {:all_requests_failed, _}} after trying" do
      result = Client.verify_enrollment_key("some-blob==", ["http://127.0.0.1:1"])
      assert {:error, {:all_requests_failed, _}} = result
    end

    test "multiple unreachable URLs → {:error, {:all_requests_failed, _}}" do
      urls = ["http://127.0.0.1:1", "http://127.0.0.1:2"]
      result = Client.verify_enrollment_key("some-blob==", urls)
      assert {:error, {:all_requests_failed, _}} = result
    end

    test "returns error tuple, not raises, when all URLs unreachable" do
      assert match?({:error, _}, Client.verify_enrollment_key("blob", ["http://127.0.0.1:1"]))
    end
  end
end
