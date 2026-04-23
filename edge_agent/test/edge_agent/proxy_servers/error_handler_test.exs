# edge_agent/test/edge_agent/proxy_servers/error_handler_test.exs
defmodule EdgeAgent.ProxyServers.ErrorHandlerTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.ProxyServers.ErrorHandler

  describe "http_error_response/1" do
    test "econnrefused → 502 connection refused" do
      assert {502, msg} = ErrorHandler.http_error_response(:econnrefused)
      assert msg =~ "Connection Refused"
    end

    test "ehostunreach → 502 host unreachable" do
      assert {502, msg} = ErrorHandler.http_error_response(:ehostunreach)
      assert msg =~ "Host Unreachable"
    end

    test "enetunreach → 502 network unreachable" do
      assert {502, msg} = ErrorHandler.http_error_response(:enetunreach)
      assert msg =~ "Network Unreachable"
    end

    test "etimedout → 504 gateway timeout" do
      assert {504, msg} = ErrorHandler.http_error_response(:etimedout)
      assert msg =~ "Timeout"
    end

    test "timeout → 504 gateway timeout" do
      assert {504, msg} = ErrorHandler.http_error_response(:timeout)
      assert msg =~ "Timeout"
    end

    test "nxdomain → 502 domain not found" do
      assert {502, msg} = ErrorHandler.http_error_response(:nxdomain)
      assert msg =~ "Domain Not Found"
    end

    test "invalid_target → 400 bad request" do
      assert {400, msg} = ErrorHandler.http_error_response(:invalid_target)
      assert msg =~ "Bad Request"
    end

    test "invalid_uri → 400 bad request" do
      assert {400, msg} = ErrorHandler.http_error_response(:invalid_uri)
      assert msg =~ "Bad Request"
    end

    test "invalid_request → 400 bad request" do
      assert {400, msg} = ErrorHandler.http_error_response(:invalid_request)
      assert msg =~ "Bad Request"
    end

    test "connect_failed → 502" do
      assert {502, msg} = ErrorHandler.http_error_response(:connect_failed)
      assert msg =~ "Connection Failed"
    end

    test "closed → 502 connection closed" do
      assert {502, msg} = ErrorHandler.http_error_response(:closed)
      assert msg =~ "Connection Closed"
    end

    test "unknown reason → 502 generic bad gateway" do
      assert {502, "Bad Gateway"} = ErrorHandler.http_error_response(:some_unknown_reason)
    end

    test "all responses have non-empty messages" do
      reasons = [
        :econnrefused,
        :ehostunreach,
        :enetunreach,
        :etimedout,
        :timeout,
        :nxdomain,
        :invalid_target,
        :invalid_uri,
        :invalid_request,
        :connect_failed,
        :closed
      ]

      for reason <- reasons do
        {_code, msg} = ErrorHandler.http_error_response(reason)
        assert is_binary(msg) and byte_size(msg) > 0, "empty message for #{reason}"
      end
    end
  end

  describe "socks5_reply_code/1" do
    test "econnrefused → 5" do
      assert ErrorHandler.socks5_reply_code(:econnrefused) == 5
    end

    test "connection_refused → 5" do
      assert ErrorHandler.socks5_reply_code(:connection_refused) == 5
    end

    test "ehostunreach → 4" do
      assert ErrorHandler.socks5_reply_code(:ehostunreach) == 4
    end

    test "host_unreachable → 4" do
      assert ErrorHandler.socks5_reply_code(:host_unreachable) == 4
    end

    test "enetunreach → 3" do
      assert ErrorHandler.socks5_reply_code(:enetunreach) == 3
    end

    test "network_unreachable → 3" do
      assert ErrorHandler.socks5_reply_code(:network_unreachable) == 3
    end

    test "unknown reason → 1 (general failure)" do
      assert ErrorHandler.socks5_reply_code(:some_unknown) == 1
    end

    test "timeout → 6 (TTL expired)" do
      assert ErrorHandler.socks5_reply_code(:timeout) == 6
      assert ErrorHandler.socks5_reply_code(:etimedout) == 6
    end
  end

  describe "categorize_error/1" do
    test "network errors: econnrefused" do
      assert ErrorHandler.categorize_error(:econnrefused) == :network
    end

    test "network errors: ehostunreach" do
      assert ErrorHandler.categorize_error(:ehostunreach) == :network
    end

    test "network errors: enetunreach" do
      assert ErrorHandler.categorize_error(:enetunreach) == :network
    end

    test "network errors: nxdomain" do
      assert ErrorHandler.categorize_error(:nxdomain) == :network
    end

    test "network errors: closed" do
      assert ErrorHandler.categorize_error(:closed) == :network
    end

    test "network errors: connection_refused alias" do
      assert ErrorHandler.categorize_error(:connection_refused) == :network
    end

    test "network errors: host_unreachable alias" do
      assert ErrorHandler.categorize_error(:host_unreachable) == :network
    end

    test "network errors: network_unreachable alias" do
      assert ErrorHandler.categorize_error(:network_unreachable) == :network
    end

    test "protocol errors: invalid_target" do
      assert ErrorHandler.categorize_error(:invalid_target) == :protocol
    end

    test "protocol errors: invalid_uri" do
      assert ErrorHandler.categorize_error(:invalid_uri) == :protocol
    end

    test "protocol errors: invalid_request" do
      assert ErrorHandler.categorize_error(:invalid_request) == :protocol
    end

    test "protocol errors: invalid_format" do
      assert ErrorHandler.categorize_error(:invalid_format) == :protocol
    end

    test "protocol errors: invalid_port" do
      assert ErrorHandler.categorize_error(:invalid_port) == :protocol
    end

    test "protocol errors: unsupported_version" do
      assert ErrorHandler.categorize_error(:unsupported_version) == :protocol
    end

    test "protocol errors: unsupported_command" do
      assert ErrorHandler.categorize_error(:unsupported_command) == :protocol
    end

    test "protocol errors: unsupported_address_type" do
      assert ErrorHandler.categorize_error(:unsupported_address_type) == :protocol
    end

    test "protocol errors: invalid_base64" do
      assert ErrorHandler.categorize_error(:invalid_base64) == :protocol
    end

    test "protocol errors: invalid_auth_type" do
      assert ErrorHandler.categorize_error(:invalid_auth_type) == :protocol
    end

    test "authentication errors: auth_failed" do
      assert ErrorHandler.categorize_error(:auth_failed) == :authentication
    end

    test "authentication errors: no_auth_header" do
      assert ErrorHandler.categorize_error(:no_auth_header) == :authentication
    end

    test "authentication errors: invalid_credentials" do
      assert ErrorHandler.categorize_error(:invalid_credentials) == :authentication
    end

    test "protocol errors: no_acceptable_methods" do
      assert ErrorHandler.categorize_error(:no_acceptable_methods) == :protocol
    end

    test "protocol errors: unsupported_auth_version" do
      assert ErrorHandler.categorize_error(:unsupported_auth_version) == :protocol
    end

    test "timeout errors: etimedout" do
      assert ErrorHandler.categorize_error(:etimedout) == :timeout
    end

    test "timeout errors: timeout" do
      assert ErrorHandler.categorize_error(:timeout) == :timeout
    end

    test "unknown: unrecognized atom" do
      assert ErrorHandler.categorize_error(:something_completely_unknown) == :unknown
    end

    test "unknown: string reason" do
      assert ErrorHandler.categorize_error("some string") == :unknown
    end
  end

  describe "telemetry_metadata/2" do
    test "returns map with correct keys" do
      meta = ErrorHandler.telemetry_metadata(:econnrefused, :http)
      assert Map.has_key?(meta, :protocol)
      assert Map.has_key?(meta, :error_reason)
      assert Map.has_key?(meta, :error_category)
    end

    test "protocol field matches argument" do
      assert %{protocol: :http} = ErrorHandler.telemetry_metadata(:timeout, :http)
      assert %{protocol: :socks5} = ErrorHandler.telemetry_metadata(:timeout, :socks5)
    end

    test "error_reason field matches argument" do
      assert %{error_reason: :econnrefused} = ErrorHandler.telemetry_metadata(:econnrefused, :http)
    end

    test "error_category is derived from reason via categorize_error" do
      assert %{error_category: :network} = ErrorHandler.telemetry_metadata(:econnrefused, :http)
      assert %{error_category: :timeout} = ErrorHandler.telemetry_metadata(:timeout, :socks5)
      assert %{error_category: :protocol} = ErrorHandler.telemetry_metadata(:invalid_uri, :http)
      assert %{error_category: :authentication} = ErrorHandler.telemetry_metadata(:auth_failed, :http)
      assert %{error_category: :unknown} = ErrorHandler.telemetry_metadata(:mystery, :http)
    end
  end
end
