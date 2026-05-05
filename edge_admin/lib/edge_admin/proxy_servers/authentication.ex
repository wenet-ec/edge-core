# edge_admin/lib/edge_admin/proxy_servers/authentication.ex
defmodule EdgeAdmin.ProxyServers.Authentication do
  @moduledoc """
  Authentication for admin proxy server.

  Determines routing mode based on username:
  - Username "_" or empty: Direct VPN access to nodes
  - Username = node DNS hostname: Proxy chaining via agent

  Password is always proxy_key for admin authentication. Comparison is
  timing-safe to avoid side-channel attacks.

  When `AUTH_ENABLED=false`, password verification is skipped entirely — any
  password (including blank) is accepted. The username branch still runs,
  so routing-mode parsing is unaffected. Intended for local dev only.
  """

  require Logger

  @nodes_module Application.compile_env(:edge_admin, :nodes_module, EdgeAdmin.Nodes)
  @compile {:no_warn_undefined, @nodes_module}

  @doc """
  Authenticate and parse proxy request.

  Returns:
  - {:ok, :direct} - Direct VPN routing
  - {:ok, :chain, node} - Proxy chaining via agent
  - {:error, reason} - Authentication failed
  """
  def authenticate_and_parse(username, password) do
    if authenticate_password(password) do
      parse_routing_mode(username)
    else
      Logger.warning("Proxy authentication failed: invalid password")
      {:error, :invalid_credentials}
    end
  end

  defp authenticate_password(password) do
    auth_enabled = Application.get_env(:edge_admin, :auth_enabled, true)

    if auth_enabled do
      stored_key = Application.get_env(:edge_admin, :proxy_key)
      secure_compare(to_string(password), to_string(stored_key || ""))
    else
      Logger.debug("Proxy authentication bypassed (auth disabled)")
      true
    end
  end

  # Constant-time binary compare via OTP's :crypto.hash_equals/2. Mismatched
  # lengths still consume a same-length compare so the rejection path doesn't
  # leak length via timing.
  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    if byte_size(a) == byte_size(b) do
      :crypto.hash_equals(a, b)
    else
      # Still consume the full-length compare to avoid leaking length. We use a
      # same-length xor with the longer side padded by the shorter.
      _ = :crypto.hash_equals(a, String.slice(b <> a, 0, byte_size(a)))
      false
    end
  end

  defp parse_routing_mode(username) do
    case username do
      "" -> {:ok, :direct}
      "_" -> {:ok, :direct}
      node_dns -> find_node_by_dns(node_dns)
    end
  end

  defp find_node_by_dns(node_dns) do
    domain = Application.get_env(:edge_admin, :netmaker_default_domain, "nm.internal")
    pattern = ~r/^node-(.+)\.(cluster-[^.]+)\.#{Regex.escape(domain)}$/

    case Regex.run(pattern, node_dns) do
      [_, identifier, network_name] ->
        cluster_name = String.replace_prefix(network_name, "cluster-", "")
        lookup_node_in_cluster(cluster_name, identifier, node_dns)

      nil ->
        Logger.warning("Invalid DNS format for proxy chaining: #{node_dns}")
        {:error, :invalid_dns_format}
    end
  end

  defp lookup_node_in_cluster(cluster_name, identifier, node_dns) do
    case @nodes_module.list_proxy_chain_identifiers(cluster_name) do
      {:ok, identifiers_map} ->
        case Map.get(identifiers_map, identifier) do
          nil ->
            Logger.warning("Node not found for proxy chaining: #{node_dns}")
            {:error, :node_not_found}

          node ->
            Logger.info("Proxy chaining via node: #{node_dns}")
            {:ok, :chain, node}
        end

      {:error, :not_found} ->
        Logger.warning("Cluster not found for proxy chaining: #{cluster_name}")
        {:error, :cluster_not_found}
    end
  end
end
