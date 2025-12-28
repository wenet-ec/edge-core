# edge_agent/lib/edge_agent/proxy_servers/error_handler.ex
defmodule EdgeAgent.ProxyServers.ErrorHandler do
  @moduledoc """
  Centralized error handling for proxy servers.

  Maps internal error reasons to protocol-specific responses and provides
  error categorization for telemetry/monitoring.
  """

  require Logger

  @doc """
  Maps error reasons to HTTP proxy response codes and messages.

  Returns {status_code, message}
  """
  def http_error_response(reason) do
    case reason do
      # Network errors
      :econnrefused -> {502, "Bad Gateway - Connection Refused"}
      :ehostunreach -> {502, "Bad Gateway - Host Unreachable"}
      :enetunreach -> {502, "Bad Gateway - Network Unreachable"}
      :etimedout -> {504, "Gateway Timeout"}
      :timeout -> {504, "Gateway Timeout"}
      :nxdomain -> {502, "Bad Gateway - Domain Not Found"}
      # Protocol/validation errors
      :invalid_target -> {400, "Bad Request - Invalid Target"}
      :invalid_uri -> {400, "Bad Request - Invalid URI"}
      :invalid_request -> {400, "Bad Request"}
      # Connection failures
      :connect_failed -> {502, "Bad Gateway - Connection Failed"}
      :closed -> {502, "Bad Gateway - Connection Closed"}
      # Generic fallback
      _ -> {502, "Bad Gateway"}
    end
  end

  @doc """
  Maps error reasons to SOCKS5 reply codes (RFC 1928).

  Returns reply_code integer
  """
  def socks5_reply_code(reason) do
    case reason do
      # Connection refused
      :econnrefused -> 5
      :connection_refused -> 5
      # Host unreachable
      :ehostunreach -> 4
      :host_unreachable -> 4
      # Network unreachable
      :enetunreach -> 3
      :network_unreachable -> 3
      # General failure
      _ -> 1
    end
  end

  @doc """
  Categorizes errors for telemetry and monitoring.

  Categories:
  - :network - Network-level connectivity issues
  - :protocol - Protocol validation/handshake failures
  - :authentication - Auth failures
  - :timeout - Timeout errors
  - :unknown - Unrecognized errors
  """
  def categorize_error(reason) do
    case reason do
      # Network errors
      r
      when r in [
             :econnrefused,
             :ehostunreach,
             :enetunreach,
             :nxdomain,
             :closed,
             :connection_refused,
             :host_unreachable,
             :network_unreachable
           ] ->
        :network

      # Protocol errors
      r
      when r in [
             :invalid_target,
             :invalid_uri,
             :invalid_request,
             :invalid_format,
             :invalid_port,
             :unsupported_version,
             :unsupported_command,
             :unsupported_address_type,
             :invalid_base64,
             :invalid_auth_type
           ] ->
        :protocol

      # Authentication errors
      r
      when r in [:auth_failed, :no_auth_header, :invalid_credentials, :no_acceptable_methods, :unsupported_auth_version] ->
        :authentication

      # Timeout errors
      r when r in [:etimedout, :timeout] ->
        :timeout

      # Unknown
      _ ->
        :unknown
    end
  end

  @doc """
  Logs error with appropriate level based on category.

  Network errors are logged as warnings (expected transient failures).
  Protocol/auth errors are logged as info (client issues, not system issues).
  Timeout errors are logged as warnings.
  Unknown errors are logged as errors.
  """
  def log_error(reason, context \\ %{}) do
    category = categorize_error(reason)
    message = build_error_message(reason, context)

    case category do
      :network ->
        Logger.warning(message, category: category, reason: reason, context: context)

      :timeout ->
        Logger.warning(message, category: category, reason: reason, context: context)

      :authentication ->
        Logger.info(message, category: category, reason: reason, context: context)

      :protocol ->
        Logger.info(message, category: category, reason: reason, context: context)

      :unknown ->
        Logger.error(message, category: category, reason: reason, context: context)
    end

    category
  end

  defp build_error_message(reason, context) do
    base = "Proxy error: #{inspect(reason)}"

    details =
      Enum.map_join(context, ", ", fn {k, v} -> "#{k}=#{inspect(v)}" end)

    if details == "" do
      base
    else
      "#{base} (#{details})"
    end
  end

  @doc """
  Builds telemetry metadata for error events.

  Returns map with error category and reason.
  """
  def telemetry_metadata(reason, protocol) do
    %{
      protocol: protocol,
      error_reason: reason,
      error_category: categorize_error(reason)
    }
  end
end
