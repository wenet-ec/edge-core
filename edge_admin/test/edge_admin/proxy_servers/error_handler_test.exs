defmodule EdgeAdmin.ProxyServers.ErrorHandlerTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.ProxyServers.ErrorHandler

  # ---------------------------------------------------------------------------
  # http_error_response/1
  # ---------------------------------------------------------------------------

  describe "http_error_response/1" do
    test "network errors return 502" do
      for reason <- [:econnrefused, :ehostunreach, :enetunreach, :nxdomain, :closed] do
        {code, _msg} = ErrorHandler.http_error_response(reason)
        assert code == 502, "expected 502 for #{reason}, got #{code}"
      end
    end

    test "timeout errors return 504" do
      for reason <- [:etimedout, :timeout] do
        {code, _msg} = ErrorHandler.http_error_response(reason)
        assert code == 504, "expected 504 for #{reason}, got #{code}"
      end
    end

    test "infrastructure errors return 503" do
      for reason <- [:no_gateway, :no_cluster_owner, :gateway_not_found] do
        {code, _msg} = ErrorHandler.http_error_response(reason)
        assert code == 503, "expected 503 for #{reason}, got #{code}"
      end
    end

    test "protocol/validation errors return 400" do
      for reason <- [:invalid_target, :invalid_uri, :invalid_request] do
        {code, _msg} = ErrorHandler.http_error_response(reason)
        assert code == 400, "expected 400 for #{reason}, got #{code}"
      end
    end

    test "unknown errors fall back to 502" do
      {code, _msg} = ErrorHandler.http_error_response(:something_totally_unknown)
      assert code == 502
    end

    test "messages are non-empty strings" do
      for reason <- [:econnrefused, :timeout, :no_gateway, :invalid_uri, :unknown_thing] do
        {_code, msg} = ErrorHandler.http_error_response(reason)
        assert is_binary(msg) and msg != ""
      end
    end
  end

  # ---------------------------------------------------------------------------
  # socks5_reply_code/1
  # ---------------------------------------------------------------------------

  describe "socks5_reply_code/1" do
    # RFC 1928 reply codes
    test "connection refused errors return code 5" do
      for reason <- [:econnrefused, :connection_refused] do
        assert ErrorHandler.socks5_reply_code(reason) == 5
      end
    end

    test "host unreachable errors return code 4" do
      for reason <- [:ehostunreach, :host_unreachable] do
        assert ErrorHandler.socks5_reply_code(reason) == 4
      end
    end

    test "network unreachable errors return code 3" do
      for reason <- [:enetunreach, :network_unreachable] do
        assert ErrorHandler.socks5_reply_code(reason) == 3
      end
    end

    test "unknown errors return general failure code 1" do
      assert ErrorHandler.socks5_reply_code(:something_else) == 1
      assert ErrorHandler.socks5_reply_code(:timeout) == 1
      assert ErrorHandler.socks5_reply_code(:no_gateway) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # categorize_error/1
  # ---------------------------------------------------------------------------

  describe "categorize_error/1" do
    test "network errors" do
      for reason <- [
            :econnrefused,
            :ehostunreach,
            :enetunreach,
            :nxdomain,
            :closed,
            :connection_refused,
            :host_unreachable,
            :network_unreachable
          ] do
        assert ErrorHandler.categorize_error(reason) == :network
      end
    end

    test "infrastructure errors" do
      for reason <- [:no_gateway, :no_cluster_owner, :gateway_not_found] do
        assert ErrorHandler.categorize_error(reason) == :infrastructure
      end
    end

    test "protocol errors" do
      for reason <- [
            :invalid_target,
            :invalid_uri,
            :invalid_request,
            :invalid_format,
            :invalid_port,
            :invalid_dns_format,
            :proxy_rejected,
            :unsupported_version,
            :unsupported_command,
            :unsupported_address_type,
            :invalid_base64,
            :invalid_auth_type
          ] do
        assert ErrorHandler.categorize_error(reason) == :protocol
      end
    end

    test "authentication errors" do
      for reason <- [
            :auth_failed,
            :no_auth_header,
            :invalid_credentials,
            :node_not_found,
            :cluster_not_found,
            :socks5_auth_failed
          ] do
        assert ErrorHandler.categorize_error(reason) == :authentication
      end
    end

    test "timeout errors" do
      for reason <- [:etimedout, :timeout] do
        assert ErrorHandler.categorize_error(reason) == :timeout
      end
    end

    test "unknown errors" do
      assert ErrorHandler.categorize_error(:completely_made_up) == :unknown
    end
  end

  # ---------------------------------------------------------------------------
  # should_trigger_degraded_mode?/1
  # ---------------------------------------------------------------------------

  describe "should_trigger_degraded_mode?/1" do
    test "infrastructure errors trigger degraded mode" do
      for reason <- [:no_gateway, :no_cluster_owner, :gateway_not_found] do
        assert ErrorHandler.should_trigger_degraded_mode?(reason) == true
      end
    end

    test "non-infrastructure errors do not trigger degraded mode" do
      for reason <- [:econnrefused, :timeout, :invalid_uri, :auth_failed, :unknown_error] do
        assert ErrorHandler.should_trigger_degraded_mode?(reason) == false
      end
    end
  end

  # ---------------------------------------------------------------------------
  # telemetry_metadata/2
  # ---------------------------------------------------------------------------

  describe "telemetry_metadata/2" do
    test "returns map with expected keys" do
      meta = ErrorHandler.telemetry_metadata(:no_gateway, :http)

      assert meta.protocol == :http
      assert meta.error_reason == :no_gateway
      assert meta.error_category == :infrastructure
      assert meta.should_degrade == true
    end

    test "should_degrade is false for non-infrastructure errors" do
      meta = ErrorHandler.telemetry_metadata(:econnrefused, :socks5)

      assert meta.should_degrade == false
      assert meta.error_category == :network
      assert meta.protocol == :socks5
    end
  end
end
