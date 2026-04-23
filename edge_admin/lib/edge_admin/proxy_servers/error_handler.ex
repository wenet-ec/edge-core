# edge_admin/lib/edge_admin/proxy_servers/error_handler.ex
defmodule EdgeAdmin.ProxyServers.ErrorHandler do
  @moduledoc """
  Centralized error handling for proxy servers.

  Three concerns that used to be tangled are now separate:

    * `http_error_response/1` / `socks5_reply_code/1` — what the client sees
      (response shape)
    * `categorize_error/1` — how ops/telemetry tags the error (category)
    * `log_error/2` / `telemetry_metadata/2` — how we log and emit metrics
  """

  require Logger

  # SOCKS5 reply codes, RFC 1928 §6
  @socks5_success 0
  @socks5_general_failure 1
  @socks5_rule_failure 2
  @socks5_network_unreachable 3
  @socks5_host_unreachable 4
  @socks5_connection_refused 5
  @socks5_ttl_expired 6
  @socks5_command_not_supported 7
  @socks5_address_type_not_supported 8

  @doc """
  Maps error reasons to HTTP proxy response codes and messages.
  """
  def http_error_response(reason) do
    case reason do
      :econnrefused -> {502, "Bad Gateway - Connection Refused"}
      :ehostunreach -> {502, "Bad Gateway - Host Unreachable"}
      :enetunreach -> {502, "Bad Gateway - Network Unreachable"}
      :etimedout -> {504, "Gateway Timeout"}
      :timeout -> {504, "Gateway Timeout"}
      :nxdomain -> {502, "Bad Gateway - Domain Not Found"}
      :no_gateway -> {503, "Service Unavailable - No Gateway"}
      :no_cluster_owner -> {503, "Service Unavailable - Cluster Unavailable"}
      :gateway_not_found -> {503, "Service Unavailable - Gateway Not Found"}
      :invalid_target -> {400, "Bad Request - Invalid Target"}
      :invalid_uri -> {400, "Bad Request - Invalid URI"}
      :invalid_request -> {400, "Bad Request"}
      :origin_form_uri -> {400, "Bad Request - Proxy Requires Absolute URI"}
      :loop_detected -> {508, "Loop Detected"}
      :localhost_blocked -> {403, "Forbidden - Localhost Blocked"}
      :link_local_blocked -> {403, "Forbidden - Link Local Blocked"}
      :metadata_service_blocked -> {403, "Forbidden - Metadata Service Blocked"}
      :blocked_port -> {403, "Forbidden - Blocked Port"}
      :proxy_rejected -> {502, "Bad Gateway - Proxy Rejected"}
      :connect_failed -> {502, "Bad Gateway - Connection Failed"}
      :closed -> {502, "Bad Gateway - Connection Closed"}
      :header_too_large -> {431, "Request Header Fields Too Large"}
      {:bad_request_line, _} -> {400, "Bad Request"}
      {:bad_header, _} -> {400, "Bad Request"}
      _ -> {502, "Bad Gateway"}
    end
  end

  @doc """
  Maps error reasons to SOCKS5 reply codes (RFC 1928).
  """
  def socks5_reply_code(reason) do
    case reason do
      :ok -> @socks5_success
      :econnrefused -> @socks5_connection_refused
      :connection_refused -> @socks5_connection_refused
      :ehostunreach -> @socks5_host_unreachable
      :host_unreachable -> @socks5_host_unreachable
      :enetunreach -> @socks5_network_unreachable
      :network_unreachable -> @socks5_network_unreachable
      :nxdomain -> @socks5_host_unreachable
      :dns_resolution_failed -> @socks5_host_unreachable
      :etimedout -> @socks5_ttl_expired
      :timeout -> @socks5_ttl_expired
      :localhost_blocked -> @socks5_rule_failure
      :link_local_blocked -> @socks5_rule_failure
      :metadata_service_blocked -> @socks5_rule_failure
      :blocked_port -> @socks5_rule_failure
      :docker_port_blocked -> @socks5_rule_failure
      :kubernetes_port_blocked -> @socks5_rule_failure
      :metrics_port_blocked -> @socks5_rule_failure
      :custom_blocked -> @socks5_rule_failure
      :unsupported_command -> @socks5_command_not_supported
      :unsupported_address_type -> @socks5_address_type_not_supported
      :no_gateway -> @socks5_general_failure
      :no_cluster_owner -> @socks5_general_failure
      :gateway_not_found -> @socks5_general_failure
      _ -> @socks5_general_failure
    end
  end

  @doc """
  Categorizes errors for telemetry and monitoring.
  """
  def categorize_error(reason) do
    cond do
      reason in network_reasons() -> :network
      reason in infrastructure_reasons() -> :infrastructure
      reason in protocol_reasons() -> :protocol
      reason in auth_reasons() -> :authentication
      reason in policy_reasons() -> :policy
      reason in timeout_reasons() -> :timeout
      match?({:bad_request_line, _}, reason) -> :protocol
      match?({:bad_header, _}, reason) -> :protocol
      match?({:http_status, _}, reason) -> :network
      match?({:socks5_connect, _}, reason) -> :network
      true -> :unknown
    end
  end

  defp network_reasons do
    [
      :econnrefused,
      :ehostunreach,
      :enetunreach,
      :nxdomain,
      :closed,
      :connection_refused,
      :host_unreachable,
      :network_unreachable,
      :dns_resolution_failed
    ]
  end

  defp infrastructure_reasons do
    [:no_gateway, :no_cluster_owner, :gateway_not_found]
  end

  defp protocol_reasons do
    [
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
      :unsupported_auth_version,
      :unsupported_method,
      :no_acceptable_methods,
      :invalid_base64,
      :invalid_auth_type,
      :origin_form_uri,
      :loop_detected,
      :header_too_large,
      :bad_response
    ]
  end

  defp auth_reasons do
    [
      :auth_failed,
      :no_auth_header,
      :invalid_credentials,
      :node_not_found,
      :cluster_not_found,
      :socks5_auth_failed
    ]
  end

  defp policy_reasons do
    [
      :localhost_blocked,
      :link_local_blocked,
      :metadata_service_blocked,
      :blocked_port,
      :docker_port_blocked,
      :kubernetes_port_blocked,
      :metrics_port_blocked,
      :custom_blocked
    ]
  end

  defp timeout_reasons, do: [:etimedout, :timeout]

  @doc """
  Determines if an error should trigger degraded mode.
  """
  def should_trigger_degraded_mode?(reason) do
    categorize_error(reason) == :infrastructure
  end

  @doc """
  Logs error with appropriate level based on category.
  """
  def log_error(reason, context \\ %{}) do
    category = categorize_error(reason)
    message = build_error_message(reason, context)

    case category do
      :infrastructure -> Logger.error(message, category: category, reason: reason, context: context)
      :network -> Logger.warning(message, category: category, reason: reason, context: context)
      :timeout -> Logger.warning(message, category: category, reason: reason, context: context)
      :policy -> Logger.info(message, category: category, reason: reason, context: context)
      _ -> Logger.info(message, category: category, reason: reason, context: context)
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
