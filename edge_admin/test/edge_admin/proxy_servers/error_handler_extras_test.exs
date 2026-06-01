# edge_admin/test/edge_admin/proxy_servers/error_handler_extras_test.exs
defmodule EdgeAdmin.ProxyServers.ErrorHandlerExtrasTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.ProxyServers.ErrorHandler

  describe "http_error_response/1 — new mappings" do
    test "origin-form URI → 400" do
      assert {400, msg} = ErrorHandler.http_error_response(:origin_form_uri)
      assert msg =~ "Absolute URI"
    end

    test "loop detected → 508" do
      assert {508, _} = ErrorHandler.http_error_response(:loop_detected)
    end

    test "SSRF-class blocks → 403" do
      for reason <- [:localhost_blocked, :link_local_blocked, :metadata_service_blocked, :blocked_port] do
        assert {403, _} = ErrorHandler.http_error_response(reason)
      end
    end

    test "non-VPN target in direct mode → 403" do
      assert {403, msg} = ErrorHandler.http_error_response(:not_vpn_target)
      assert msg =~ "VPN Hostname"
    end

    test "header_too_large → 431" do
      assert {431, _} = ErrorHandler.http_error_response(:header_too_large)
    end
  end

  describe "socks5_reply_code/1 — expanded mapping" do
    test "connection refused → 5" do
      assert 5 == ErrorHandler.socks5_reply_code(:econnrefused)
    end

    test "host unreachable → 4" do
      assert 4 == ErrorHandler.socks5_reply_code(:ehostunreach)
      assert 4 == ErrorHandler.socks5_reply_code(:nxdomain)
      assert 4 == ErrorHandler.socks5_reply_code(:dns_resolution_failed)
    end

    test "network unreachable → 3" do
      assert 3 == ErrorHandler.socks5_reply_code(:enetunreach)
    end

    test "policy blocks → 2 (rule failure)" do
      assert 2 == ErrorHandler.socks5_reply_code(:localhost_blocked)
      assert 2 == ErrorHandler.socks5_reply_code(:metadata_service_blocked)
      assert 2 == ErrorHandler.socks5_reply_code(:custom_blocked)
    end

    test "timeout → 6 (TTL expired)" do
      assert 6 == ErrorHandler.socks5_reply_code(:etimedout)
      assert 6 == ErrorHandler.socks5_reply_code(:timeout)
    end

    test "unsupported command → 7" do
      assert 7 == ErrorHandler.socks5_reply_code(:unsupported_command)
    end

    test "unsupported address type → 8" do
      assert 8 == ErrorHandler.socks5_reply_code(:unsupported_address_type)
    end

    test "unknown reason falls back to 1" do
      assert 1 == ErrorHandler.socks5_reply_code(:something_weird)
    end
  end

  describe "categorize_error/1 — policy category" do
    test "policy blocks categorized as :policy, not :authentication" do
      assert :policy == ErrorHandler.categorize_error(:localhost_blocked)
      assert :policy == ErrorHandler.categorize_error(:metadata_service_blocked)
      assert :protocol == ErrorHandler.categorize_error(:not_vpn_target)
    end

    test "origin_form_uri and loop_detected are protocol errors" do
      assert :protocol == ErrorHandler.categorize_error(:origin_form_uri)
      assert :protocol == ErrorHandler.categorize_error(:loop_detected)
    end
  end
end
