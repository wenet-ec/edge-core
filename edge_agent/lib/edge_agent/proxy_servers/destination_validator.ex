# edge_agent/lib/edge_agent/proxy_servers/destination_validator.ex
defmodule EdgeAgent.ProxyServers.DestinationValidator do
  @moduledoc """
  Validates proxy destination addresses to prevent SSRF and privilege escalation attacks.

  Security Model:
  - BLOCK: Localhost/loopback (127.0.0.0/8, ::1, localhost)
  - BLOCK: Cloud metadata services (169.254.169.254, metadata.google.internal, etc.)
  - BLOCK: Link-local addresses (169.254.0.0/16)
  - BLOCK: Docker networks (10.0.0.0/8, 172.16.0.0/12)
  - BLOCK: Docker API ports (2375, 2376, 2377)
  - BLOCK: Kubernetes API ports (6443, 8080, 10250, 10255)
  - BLOCK: Agent's own service ports (configurable)
  - ALLOW: LAN networks only (192.168.0.0/16)
  - ALLOW: Public internet
  - ALLOW: Custom allow list (overrides all blocks)

  ## Configuration

  Add to runtime.exs:

      config :edge_agent,
        proxy_blocked_ports: [44000, 44880, 44180],  # Agent's own ports
        proxy_custom_blocked_hosts: [],  # Additional hosts to block
        proxy_custom_allowed_hosts: []   # Exceptions to blocking rules
  """

  require Logger

  # Localhost patterns
  @localhost_patterns [
    "localhost",
    "127.0.0.1",
    "0.0.0.0",
    "::1",
    "::ffff:127.0.0.1"
  ]

  # Cloud metadata service hostnames
  @metadata_hostnames [
    "metadata.google.internal",
    "metadata.azure.com",
    "169.254.169.254"
  ]

  # Docker API ports
  @docker_ports [2375, 2376, 2377]

  # Kubernetes API ports
  @kubernetes_ports [
    # K8s API server
    6443,
    # K8s API server (insecure)
    8080,
    # Kubelet API
    10_250,
    # Kubelet read-only
    10_255,
    # Etcd client
    2379,
    # Etcd peer
    2380
  ]

  @doc """
  Validates a destination host and port.

  Returns:
  - :ok if allowed
  - {:error, reason} if blocked
  """
  def validate_destination(host, port) when is_binary(host) and is_integer(port) do
    cond do
      # Check custom allow list first (highest priority)
      custom_allowed?(host, port) ->
        Logger.debug("Proxy destination allowed (custom allowlist): #{host}:#{port}")
        :ok

      # Check localhost blocking
      localhost?(host) ->
        Logger.warning("Proxy destination BLOCKED (localhost): #{host}:#{port}")
        {:error, :localhost_blocked}

      # Check cloud metadata services
      metadata_service?(host) ->
        Logger.warning("Proxy destination BLOCKED (metadata service): #{host}:#{port}")
        {:error, :metadata_service_blocked}

      # Check link-local addresses (169.254.0.0/16)
      link_local?(host) ->
        Logger.warning("Proxy destination BLOCKED (link-local address): #{host}:#{port}")
        {:error, :link_local_blocked}

      # Check Docker internal networks (10.0.0.0/8, 172.16.0.0/12)
      docker_network?(host) ->
        Logger.warning("Proxy destination BLOCKED (Docker/container network): #{host}:#{port}")
        {:error, :docker_network_blocked}

      # Check Docker API ports
      docker_port?(port) ->
        Logger.warning("Proxy destination BLOCKED (Docker API port): #{host}:#{port}")
        {:error, :docker_port_blocked}

      # Check Kubernetes API ports
      kubernetes_port?(port) ->
        Logger.warning("Proxy destination BLOCKED (Kubernetes API port): #{host}:#{port}")
        {:error, :kubernetes_port_blocked}

      # Check sensitive metrics ports (always blocked)
      metrics_port?(port) ->
        Logger.warning("Proxy destination BLOCKED (metrics port): #{host}:#{port}")
        {:error, :metrics_port_blocked}

      # Check custom block list (user-configured)
      custom_blocked?(host, port) ->
        Logger.warning("Proxy destination BLOCKED (custom blocklist): #{host}:#{port}")
        {:error, :custom_blocked}

      # All other destinations allowed (LAN 192.168.x.x and public internet)
      true ->
        Logger.debug("Proxy destination allowed: #{host}:#{port}")
        :ok
    end
  end

  @doc """
  Check if host is localhost/loopback.

  Supports:
  - String patterns (localhost, 127.0.0.1, etc.)
  - IP address parsing for 127.0.0.0/8 range
  - IPv6 loopback (::1)
  """
  def localhost?(host) do
    cond do
      # Check exact string matches
      String.downcase(host) in @localhost_patterns ->
        true

      # Check if it's in 127.0.0.0/8 range
      String.starts_with?(host, "127.") ->
        true

      # Check IPv6 loopback variations
      String.contains?(String.downcase(host), "::1") ->
        true

      # Try parsing as IP and check loopback
      match?({127, _, _, _}, parse_ipv4(host)) ->
        true

      true ->
        false
    end
  end

  @doc """
  Check if host is a cloud metadata service.
  """
  def metadata_service?(host) do
    host_lower = String.downcase(host)

    Enum.any?(@metadata_hostnames, fn pattern ->
      host_lower == String.downcase(pattern)
    end)
  end

  @doc """
  Check if host is a link-local address (169.254.0.0/16).
  """
  def link_local?(host) do
    case parse_ipv4(host) do
      {169, 254, _, _} -> true
      _ -> false
    end
  end

  @doc """
  Check if host is in Docker internal networks.

  Blocks:
  - 10.0.0.0/8 (Docker default bridge networks)
  - 172.16.0.0/12 (Docker user-defined bridge networks)
  """
  def docker_network?(host) do
    case parse_ipv4(host) do
      # 10.0.0.0/8
      {10, _, _, _} ->
        true

      # 172.16.0.0/12 (172.16.0.0 - 172.31.255.255)
      {172, second, _, _} when second >= 16 and second <= 31 ->
        true

      _ ->
        false
    end
  end

  @doc """
  Check if port is a Docker API port.
  """
  def docker_port?(port), do: port in @docker_ports

  @doc """
  Check if port is a Kubernetes API port.
  """
  def kubernetes_port?(port), do: port in @kubernetes_ports

  @doc """
  Check if port is a sensitive metrics port (always blocked).

  These ports expose sensitive host/network data and should never be proxied:
  - host_metrics_port (default 49_100) - Node Exporter metrics
  - wireguard_metrics_port (default 49_586) - WireGuard interface metrics
  """
  def metrics_port?(port) do
    host_metrics_port = Application.get_env(:edge_agent, :host_metrics_port)
    wireguard_metrics_port = Application.get_env(:edge_agent, :wireguard_metrics_port)

    port in [host_metrics_port, wireguard_metrics_port]
  end

  @doc """
  Check if host:port is in custom block list (user-configured).

  Supports two formats via PROXY_CUSTOM_BLOCKED_HOSTS env:
  - Host only: ["badhost.com", "evil.net"] - blocks all ports
  - Host + port: [{"internal-db.local", 5432}, {"cache.local", 6379}]

  Also checks PROXY_BLOCKED_PORTS env for additional port-only blocks.
  """
  def custom_blocked?(host, port) do
    # Check host-based blocks
    custom_blocked_hosts = Application.get_env(:edge_agent, :proxy_custom_blocked_hosts, [])

    host_blocked =
      Enum.any?(custom_blocked_hosts, fn
        {blocked_host, blocked_port} ->
          String.downcase(host) == String.downcase(blocked_host) and port == blocked_port

        blocked_host when is_binary(blocked_host) ->
          String.downcase(host) == String.downcase(blocked_host)
      end)

    # Check port-only blocks
    custom_blocked_ports = Application.get_env(:edge_agent, :proxy_blocked_ports, [])
    port_blocked = port in custom_blocked_ports

    host_blocked or port_blocked
  end

  @doc """
  Check if host:port is in custom allow list (bypasses all other checks).
  """
  def custom_allowed?(host, port) do
    custom_allowed_hosts = Application.get_env(:edge_agent, :proxy_custom_allowed_hosts, [])

    Enum.any?(custom_allowed_hosts, fn
      {allowed_host, allowed_port} ->
        String.downcase(host) == String.downcase(allowed_host) and port == allowed_port

      allowed_host when is_binary(allowed_host) ->
        String.downcase(host) == String.downcase(allowed_host)
    end)
  end

  # Parse IPv4 address string to tuple
  defp parse_ipv4(host) do
    case String.split(host, ".") do
      [a, b, c, d] ->
        with {a_int, ""} <- Integer.parse(a),
             {b_int, ""} <- Integer.parse(b),
             {c_int, ""} <- Integer.parse(c),
             {d_int, ""} <- Integer.parse(d) do
          {a_int, b_int, c_int, d_int}
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Get human-readable error message for blocked reason.
  """
  def error_message(reason) do
    case reason do
      :localhost_blocked ->
        "Access to localhost/loopback addresses is blocked for security"

      :metadata_service_blocked ->
        "Access to cloud metadata services is blocked for security"

      :link_local_blocked ->
        "Access to link-local addresses is blocked for security"

      :docker_network_blocked ->
        "Access to Docker/container internal networks is blocked for security"

      :docker_port_blocked ->
        "Access to Docker API ports is blocked for security"

      :kubernetes_port_blocked ->
        "Access to Kubernetes API ports is blocked for security"

      :metrics_port_blocked ->
        "Access to metrics ports is blocked for security"

      :custom_blocked ->
        "Access to this destination is blocked by policy"

      _ ->
        "Access blocked"
    end
  end
end
