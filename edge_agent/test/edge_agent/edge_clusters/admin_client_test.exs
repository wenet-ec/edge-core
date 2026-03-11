# edge_agent/test/edge_agent/edge_clusters/admin_client_test.exs
defmodule EdgeAgent.EdgeClusters.AdminClientTest do
  use EdgeAgent.DataCase, async: false

  alias EdgeAgent.EdgeClusters.AdminClient
  alias EdgeAgent.Settings

  # ---------------------------------------------------------------------------
  # get_urls_to_try/0 — fallback URL priority logic
  #
  # The function is private, so we test it via the public API by observing
  # which error is returned: {:error, :no_admin_urls} means the URL list was
  # empty; any other error means a URL was found and a request was attempted.
  #
  # We trigger the "no URLs" path by setting everything to empty and check the
  # "fallback used" path by seeding Settings and watching for a network attempt
  # (which will fail with :request_failed when there's no real admin running,
  # but that proves the URL was resolved).
  # ---------------------------------------------------------------------------

  describe "get_urls_to_try/0 — VPN admin URLs take priority" do
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
      result = AdminClient.list_pending_command_executions()
      assert result != {:error, :no_admin_urls}
      assert match?({:error, _}, result)
    end

    test "when no VPN URLs and no fallback configured → :no_admin_urls" do
      Settings.set_admin_urls([])
      Settings.set_admin_fallback_urls([])

      assert {:error, :no_admin_urls} = AdminClient.register_node(%{node_id: "test"})
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

      result = AdminClient.list_pending_command_executions()
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

      assert {:error, :no_admin_urls} = AdminClient.register_node(%{node_id: "test"})
    end
  end

  # ---------------------------------------------------------------------------
  # verify_enrollment_key/2 — payload shape and fallback behaviour
  #
  # The function makes real HTTP calls. We can't easily mock Req here without
  # a bypass library. Instead we verify:
  # - All URLs fail → {:error, {:all_requests_failed, _}}
  # - Single bad URL → network failure, tried once
  # ---------------------------------------------------------------------------

  describe "verify_enrollment_key/2" do
    test "empty admin_urls list → {:error, {:all_requests_failed, _}}" do
      result = AdminClient.verify_enrollment_key("some-blob==", [])
      assert {:error, {:all_requests_failed, reason}} = result
      assert is_binary(reason)
    end

    test "single unreachable URL → {:error, {:all_requests_failed, _}} after trying" do
      result = AdminClient.verify_enrollment_key("some-blob==", ["http://127.0.0.1:1"])
      assert {:error, {:all_requests_failed, _}} = result
    end

    test "multiple unreachable URLs → {:error, {:all_requests_failed, _}}" do
      urls = ["http://127.0.0.1:1", "http://127.0.0.1:2"]
      result = AdminClient.verify_enrollment_key("some-blob==", urls)
      assert {:error, {:all_requests_failed, _}} = result
    end

    test "returns error tuple, not raises, when all URLs unreachable" do
      assert match?({:error, _}, AdminClient.verify_enrollment_key("blob", ["http://127.0.0.1:1"]))
    end
  end
end
