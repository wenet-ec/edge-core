# edge_admin/lib/edge_admin/proxy_servers/error_handler.ex
defmodule EdgeAdmin.ProxyServers.ErrorHandler do
  @moduledoc """
  Centralized error handling for proxy servers.

  Maps internal error reasons to protocol-specific responses and provides
  error categorization for telemetry/monitoring and degraded mode handling.
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

      # Infrastructure errors (should trigger degraded mode)
      :no_gateway -> {503, "Service Unavailable - No Gateway"}
      :no_cluster_owner -> {503, "Service Unavailable - Cluster Unavailable"}
      :gateway_not_found -> {503, "Service Unavailable - Gateway Not Found"}

      # Protocol/validation errors
      :invalid_target -> {400, "Bad Request - Invalid Target"}
      :invalid_uri -> {400, "Bad Request - Invalid URI"}
      :invalid_request -> {400, "Bad Request"}
      :proxy_rejected -> {502, "Bad Gateway - Proxy Rejected"}

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
      :econnrefused -> 5  # Connection refused
      :connection_refused -> 5
      :ehostunreach -> 4  # Host unreachable
      :host_unreachable -> 4
      :enetunreach -> 3  # Network unreachable
      :network_unreachable -> 3
      _ -> 1  # General failure
    end
  end

  @doc """
  Categorizes errors for telemetry and monitoring.

  Categories:
  - :network - Network-level connectivity issues
  - :infrastructure - Gateway/cluster availability issues (trigger degraded mode)
  - :protocol - Protocol validation/handshake failures
  - :authentication - Auth failures
  - :timeout - Timeout errors
  - :unknown - Unrecognized errors
  """
  def categorize_error(reason) do
    case reason do
      # Network errors
      r when r in [:econnrefused, :ehostunreach, :enetunreach, :nxdomain, :closed, :connection_refused, :host_unreachable, :network_unreachable] ->
        :network

      # Infrastructure errors (degraded mode triggers)
      r when r in [:no_gateway, :no_cluster_owner, :gateway_not_found] ->
        :infrastructure

      # Protocol errors
      r when r in [:invalid_target, :invalid_uri, :invalid_request, :invalid_format, :invalid_port, :invalid_dns_format, :proxy_rejected, :unsupported_version, :unsupported_command, :unsupported_address_type, :invalid_base64, :invalid_auth_type] ->
        :protocol

      # Authentication errors
      r when r in [:auth_failed, :no_auth_header, :invalid_credentials, :node_not_found, :cluster_not_found, :socks5_auth_failed] ->
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
  Determines if an error should trigger degraded mode.

  Infrastructure errors (no gateway, cluster unavailable) should trigger degraded mode.
  """
  def should_trigger_degraded_mode?(reason) do
    categorize_error(reason) == :infrastructure
  end

  @doc """
  Logs error with appropriate level based on category.

  Infrastructure errors are logged as errors (critical for ops).
  Network errors are logged as warnings (expected transient failures).
  Protocol/auth errors are logged as info (client issues, not system issues).
  """
  def log_error(reason, context \\ %{}) do
    category = categorize_error(reason)
    message = build_error_message(reason, context)

    case category do
      :infrastructure ->
        Logger.error(message, category: category, reason: reason, context: context)

      :network ->
        Logger.warning(message, category: category, reason: reason, context: context)

      :timeout ->
        Logger.warning(message, category: category, reason: reason, context: context)

      _ ->
        Logger.info(message, category: category, reason: reason, context: context)
    end

    category
  end

  defp build_error_message(reason, context) do
    base = "Proxy error: #{inspect(reason)}"

    details =
      context
      |> Enum.map(fn {k, v} -> "#{k}=#{inspect(v)}" end)
      |> Enum.join(", ")

    if details == "" do
      base
    else
      "#{base} (#{details})"
    end
  end

  @doc """
  Builds telemetry metadata for error events.

  Returns map with error category, reason, and degraded mode flag.
  """
  def telemetry_metadata(reason, protocol) do
    %{
      protocol: protocol,
      error_reason: reason,
      error_category: categorize_error(reason),
      should_degrade: should_trigger_degraded_mode?(reason)
    }
  end
end
