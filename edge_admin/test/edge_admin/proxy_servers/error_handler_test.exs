defmodule EdgeAdmin.ProxyServers.ErrorHandlerTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.ProxyServers.ErrorHandler

  describe "http_error_response/1" do
    test "returns 502 for connection refused" do
      assert {502, message} = ErrorHandler.http_error_response(:econnrefused)
      assert message =~ "Connection Refused"
    end

    test "returns 502 for host unreachable" do
      assert {502, message} = ErrorHandler.http_error_response(:ehostunreach)
      assert message =~ "Host Unreachable"
    end

    test "returns 502 for network unreachable" do
      assert {502, message} = ErrorHandler.http_error_response(:enetunreach)
      assert message =~ "Network Unreachable"
    end

    test "returns 504 for timeout errors" do
      assert {504, message} = ErrorHandler.http_error_response(:etimedout)
      assert message =~ "Timeout"

      assert {504, message} = ErrorHandler.http_error_response(:timeout)
      assert message =~ "Timeout"
    end

    test "returns 502 for DNS errors" do
      assert {502, message} = ErrorHandler.http_error_response(:nxdomain)
      assert message =~ "Domain Not Found"
    end

    test "returns 503 for infrastructure errors" do
      assert {503, message} = ErrorHandler.http_error_response(:no_gateway)
      assert message =~ "No Gateway"

      assert {503, message} = ErrorHandler.http_error_response(:no_cluster_owner)
      assert message =~ "Cluster Unavailable"

      assert {503, message} = ErrorHandler.http_error_response(:gateway_not_found)
      assert message =~ "Gateway Not Found"
    end

    test "returns 400 for protocol errors" do
      assert {400, message} = ErrorHandler.http_error_response(:invalid_target)
      assert message =~ "Invalid Target"

      assert {400, message} = ErrorHandler.http_error_response(:invalid_uri)
      assert message =~ "Invalid URI"

      assert {400, message} = ErrorHandler.http_error_response(:invalid_request)
      assert message =~ "Bad Request"
    end

    test "returns 502 for connection failures" do
      assert {502, message} = ErrorHandler.http_error_response(:connect_failed)
      assert message =~ "Connection Failed"

      assert {502, message} = ErrorHandler.http_error_response(:closed)
      assert message =~ "Connection Closed"

      assert {502, message} = ErrorHandler.http_error_response(:proxy_rejected)
      assert message =~ "Proxy Rejected"
    end

    test "returns 502 for unknown errors" do
      assert {502, message} = ErrorHandler.http_error_response(:unknown_error)
      assert message =~ "Bad Gateway"
    end
  end

  describe "socks5_reply_code/1" do
    test "returns 5 for connection refused" do
      assert ErrorHandler.socks5_reply_code(:econnrefused) == 5
      assert ErrorHandler.socks5_reply_code(:connection_refused) == 5
    end

    test "returns 4 for host unreachable" do
      assert ErrorHandler.socks5_reply_code(:ehostunreach) == 4
      assert ErrorHandler.socks5_reply_code(:host_unreachable) == 4
    end

    test "returns 3 for network unreachable" do
      assert ErrorHandler.socks5_reply_code(:enetunreach) == 3
      assert ErrorHandler.socks5_reply_code(:network_unreachable) == 3
    end

    test "returns 1 for general failures" do
      assert ErrorHandler.socks5_reply_code(:timeout) == 1
      assert ErrorHandler.socks5_reply_code(:unknown_error) == 1
      assert ErrorHandler.socks5_reply_code(:invalid_target) == 1
    end
  end

  describe "categorize_error/1" do
    test "categorizes network errors" do
      network_errors = [
        :econnrefused,
        :ehostunreach,
        :enetunreach,
        :nxdomain,
        :closed,
        :connection_refused,
        :host_unreachable,
        :network_unreachable
      ]

      for error <- network_errors do
        assert ErrorHandler.categorize_error(error) == :network,
               "Expected #{inspect(error)} to be categorized as :network"
      end
    end

    test "categorizes infrastructure errors" do
      infrastructure_errors = [
        :no_gateway,
        :no_cluster_owner,
        :gateway_not_found
      ]

      for error <- infrastructure_errors do
        assert ErrorHandler.categorize_error(error) == :infrastructure,
               "Expected #{inspect(error)} to be categorized as :infrastructure"
      end
    end

    test "categorizes protocol errors" do
      protocol_errors = [
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
      ]

      for error <- protocol_errors do
        assert ErrorHandler.categorize_error(error) == :protocol,
               "Expected #{inspect(error)} to be categorized as :protocol"
      end
    end

    test "categorizes authentication errors" do
      auth_errors = [
        :auth_failed,
        :no_auth_header,
        :invalid_credentials,
        :node_not_found,
        :cluster_not_found,
        :socks5_auth_failed
      ]

      for error <- auth_errors do
        assert ErrorHandler.categorize_error(error) == :authentication,
               "Expected #{inspect(error)} to be categorized as :authentication"
      end
    end

    test "categorizes timeout errors" do
      timeout_errors = [:etimedout, :timeout]

      for error <- timeout_errors do
        assert ErrorHandler.categorize_error(error) == :timeout,
               "Expected #{inspect(error)} to be categorized as :timeout"
      end
    end

    test "categorizes unknown errors" do
      assert ErrorHandler.categorize_error(:some_random_error) == :unknown
      assert ErrorHandler.categorize_error(:foobar) == :unknown
    end
  end

  describe "should_trigger_degraded_mode?/1" do
    test "returns true for infrastructure errors" do
      assert ErrorHandler.should_trigger_degraded_mode?(:no_gateway) == true
      assert ErrorHandler.should_trigger_degraded_mode?(:no_cluster_owner) == true
      assert ErrorHandler.should_trigger_degraded_mode?(:gateway_not_found) == true
    end

    test "returns false for network errors" do
      assert ErrorHandler.should_trigger_degraded_mode?(:econnrefused) == false
      assert ErrorHandler.should_trigger_degraded_mode?(:ehostunreach) == false
      assert ErrorHandler.should_trigger_degraded_mode?(:timeout) == false
    end

    test "returns false for protocol errors" do
      assert ErrorHandler.should_trigger_degraded_mode?(:invalid_target) == false
      assert ErrorHandler.should_trigger_degraded_mode?(:invalid_uri) == false
    end

    test "returns false for authentication errors" do
      assert ErrorHandler.should_trigger_degraded_mode?(:auth_failed) == false
      assert ErrorHandler.should_trigger_degraded_mode?(:invalid_credentials) == false
    end

    test "returns false for unknown errors" do
      assert ErrorHandler.should_trigger_degraded_mode?(:unknown_error) == false
    end
  end

  describe "telemetry_metadata/2" do
    test "builds metadata for network error" do
      metadata = ErrorHandler.telemetry_metadata(:econnrefused, :http)

      assert metadata.protocol == :http
      assert metadata.error_reason == :econnrefused
      assert metadata.error_category == :network
      assert metadata.should_degrade == false
    end

    test "builds metadata for infrastructure error" do
      metadata = ErrorHandler.telemetry_metadata(:no_gateway, :socks5)

      assert metadata.protocol == :socks5
      assert metadata.error_reason == :no_gateway
      assert metadata.error_category == :infrastructure
      assert metadata.should_degrade == true
    end

    test "builds metadata for authentication error" do
      metadata = ErrorHandler.telemetry_metadata(:auth_failed, :http)

      assert metadata.protocol == :http
      assert metadata.error_reason == :auth_failed
      assert metadata.error_category == :authentication
      assert metadata.should_degrade == false
    end

    test "builds metadata for timeout error" do
      metadata = ErrorHandler.telemetry_metadata(:timeout, :http)

      assert metadata.protocol == :http
      assert metadata.error_reason == :timeout
      assert metadata.error_category == :timeout
      assert metadata.should_degrade == false
    end
  end
end
