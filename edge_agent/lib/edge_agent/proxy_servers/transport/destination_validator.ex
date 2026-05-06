# edge_agent/lib/edge_agent/proxy_servers/transport/destination_validator.ex
defmodule EdgeAgent.ProxyServers.Transport.DestinationValidator do
  @moduledoc """
  Validates proxy destination addresses to prevent SSRF and privilege escalation attacks.

  Security Model:
  - BLOCK: Localhost/loopback (127.0.0.0/8, ::1, `localhost`, and `0.0.0.0`
    which routes to loopback on Linux)
  - BLOCK: Cloud metadata services (169.254.169.254, 100.100.100.200,
    metadata.google.internal, etc.)
  - BLOCK: Link-local addresses (169.254.0.0/16, fe80::/10)
  - BLOCK: Docker API ports (2375, 2376, 2377)
  - BLOCK: Kubernetes API ports (6443, 10250, 10255, 2379, 2380)
  - BLOCK: Agent's own metrics ports (`HOST_METRICS_PORT`,
    `WIREGUARD_METRICS_PORT` — always blocked, no opt-out)
  - BLOCK: `proxy_blocked_ports` / `proxy_custom_blocked_hosts`
    (operator-configured; both default empty — no extra ports/hosts blocked
    out of the box)
  - ALLOW: Private networks (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
  - ALLOW: Public internet
  - ALLOW: Custom allow list (overrides all blocks)

  ## DNS-rebinding posture

  `resolve_and_validate/2` performs DNS resolution **once**, validates every
  returned A and AAAA record, and then connects to a specific resolved IP
  tuple — eliminating the rebinding window between validation and connect.

  IPv4-mapped IPv6 addresses (`::ffff:a.b.c.d`) are normalised to their IPv4
  form before any range check, so a literal like `::ffff:169.254.169.254`
  cannot bypass the link-local / metadata blocklists.

  Hostnames are matched case-insensitively with trailing dots stripped, so
  `Metadata.Google.Internal.` is treated identically to `metadata.google.internal`.

  ## Configuration

  All three knobs default to empty lists — operators opt in via env vars:

      PROXY_BLOCKED_PORTS=44000,43128,41080  # Often-recommended: agent's own ports
      PROXY_CUSTOM_BLOCKED_HOSTS=...          # Additional hosts to block
      PROXY_CUSTOM_ALLOWED_HOSTS=...          # Exceptions to blocking rules

  These map to `:edge_agent` application config keys
  `:proxy_blocked_ports`, `:proxy_custom_blocked_hosts`, and
  `:proxy_custom_allowed_hosts` respectively.
  """

  require Logger

  # Hostname patterns that resolve to loopback (string-domain checks).
  @localhost_hostnames ["localhost", "ip6-localhost", "ip6-loopback"]

  # Cloud metadata service hostnames (string-domain checks).
  # IP literals for metadata services are caught structurally below.
  @metadata_hostnames [
    "metadata.google.internal",
    "metadata.azure.com",
    "metadata.azure.internal",
    "metadata.tencentyun.com"
  ]

  # Cloud metadata IPs — checked structurally against the parsed IP tuple.
  @metadata_ips [
    # AWS, OpenStack, GCE, Azure (IMDSv1/v2)
    {169, 254, 169, 254},
    # Alibaba Cloud
    {100, 100, 100, 200}
  ]

  # Docker API ports
  @docker_ports [2375, 2376, 2377]

  # Kubernetes API ports
  @kubernetes_ports [
    # K8s API server
    6443,
    # Kubelet API
    10_250,
    # Kubelet read-only
    10_255,
    # Etcd client
    2379,
    # Etcd peer
    2380
  ]

  @typep ip_tuple :: :inet.ip4_address() | :inet.ip6_address()
  @typep block_reason ::
           :localhost_blocked
           | :metadata_service_blocked
           | :link_local_blocked
           | :docker_port_blocked
           | :kubernetes_port_blocked
           | :metrics_port_blocked
           | :custom_blocked
           | :dns_resolution_failed
           | :invalid_address

  @doc """
  Resolves a hostname, validates every A and AAAA record returned, and
  returns a single IP tuple that is safe to connect to.

  This is the function call sites should use: it eliminates the DNS-rebinding
  window between validation and `:gen_tcp.connect/4` because the IP tuple
  this returns is the exact tuple the caller will connect to (no further DNS
  lookup happens inside `gen_tcp`).

  Behaviour:
    * For literal IP strings, the IP is parsed and validated directly.
    * For hostnames, *all* resolved IPs (both `:inet` and `:inet6`) are
      checked. If any one of them is denied, the entire host is denied —
      a hostname with mixed safe/unsafe records is unsafe.
    * The custom allow-list (matched on the original host string + port) is
      consulted first and bypasses all other checks, including DNS.

  Returns:
    * `{:ok, ip_tuple}` — safe to connect to `ip_tuple`
    * `{:error, reason}` — denied or DNS resolution failed
  """
  @spec resolve_and_validate(String.t(), :inet.port_number()) ::
          {:ok, ip_tuple()} | {:error, block_reason()}
  def resolve_and_validate(host, port) when is_binary(host) and is_integer(port) do
    cond do
      custom_allowed?(host, port) ->
        # Allow-list bypasses all blocks. Still need an IP tuple to connect to.
        case resolve_any(host) do
          {:ok, [ip | _]} ->
            Logger.debug("Proxy destination allowed (custom allowlist): #{host}:#{port}")
            {:ok, ip}

          {:error, _} ->
            Logger.warning("Proxy destination DNS resolution failed: #{host}:#{port}")
            {:error, :dns_resolution_failed}
        end

      reason = host_port_block_reason(host, port) ->
        Logger.warning("Proxy destination BLOCKED (#{reason}): #{host}:#{port}")
        {:error, reason}

      true ->
        # Resolve all IPs, validate every one, return the first safe IP.
        case resolve_any(host) do
          {:ok, ips} ->
            check_all_ips(ips, host, port)

          {:error, _} ->
            Logger.warning("Proxy destination DNS resolution failed: #{host}:#{port}")
            {:error, :dns_resolution_failed}
        end
    end
  end

  @doc """
  Validates a destination host and port (string-domain only — no DNS).

  Production proxy code uses `resolve_and_validate/2` instead, which closes
  the DNS-rebinding window between validation and `:gen_tcp.connect/4`.
  This function remains as a predicate-only helper for tests and callers
  that don't connect afterwards (e.g. precomputing block reasons for
  reporting).

  Returns:
    * `:ok` if allowed
    * `{:error, reason}` if blocked
  """
  @spec validate_destination(String.t(), :inet.port_number()) :: :ok | {:error, block_reason()}
  def validate_destination(host, port) when is_binary(host) and is_integer(port) do
    cond do
      custom_allowed?(host, port) ->
        Logger.debug("Proxy destination allowed (custom allowlist): #{host}:#{port}")
        :ok

      localhost?(host) ->
        Logger.warning("Proxy destination BLOCKED (localhost): #{host}:#{port}")
        {:error, :localhost_blocked}

      metadata_service?(host) ->
        Logger.warning("Proxy destination BLOCKED (metadata service): #{host}:#{port}")
        {:error, :metadata_service_blocked}

      link_local?(host) ->
        Logger.warning("Proxy destination BLOCKED (link-local address): #{host}:#{port}")
        {:error, :link_local_blocked}

      docker_port?(port) ->
        Logger.warning("Proxy destination BLOCKED (Docker API port): #{host}:#{port}")
        {:error, :docker_port_blocked}

      kubernetes_port?(port) ->
        Logger.warning("Proxy destination BLOCKED (Kubernetes API port): #{host}:#{port}")
        {:error, :kubernetes_port_blocked}

      metrics_port?(port) ->
        Logger.warning("Proxy destination BLOCKED (metrics port): #{host}:#{port}")
        {:error, :metrics_port_blocked}

      custom_blocked?(host, port) ->
        Logger.warning("Proxy destination BLOCKED (custom blocklist): #{host}:#{port}")
        {:error, :custom_blocked}

      true ->
        Logger.debug("Proxy destination allowed: #{host}:#{port}")
        :ok
    end
  end

  # -------------------------------------------------------------------------
  # Predicate API (string-domain — kept for backwards compatibility)
  # -------------------------------------------------------------------------

  @doc """
  Check if `host` is a loopback address or hostname.

  Accepts a hostname or an IP literal as a string. IPv4-mapped IPv6
  (`::ffff:127.0.0.1`) collapses to its IPv4 form before checking.
  """
  @spec localhost?(String.t()) :: boolean()
  def localhost?(host) when is_binary(host) do
    case parse_address(host) do
      {:ok, ip} -> loopback_ip?(ip)
      :error -> hostname_loopback?(host)
    end
  end

  @doc """
  Check if `host` is a known cloud metadata service (by hostname or IP literal).
  """
  @spec metadata_service?(String.t()) :: boolean()
  def metadata_service?(host) when is_binary(host) do
    case parse_address(host) do
      {:ok, ip} -> metadata_ip?(ip)
      :error -> hostname_metadata?(host)
    end
  end

  @doc """
  Check if `host` is a link-local address (IPv4 169.254.0.0/16 or IPv6 fe80::/10).
  """
  @spec link_local?(String.t()) :: boolean()
  def link_local?(host) when is_binary(host) do
    case parse_address(host) do
      {:ok, ip} -> link_local_ip?(ip)
      :error -> false
    end
  end

  @doc """
  Check if `port` is a Docker API port.
  """
  @spec docker_port?(:inet.port_number()) :: boolean()
  def docker_port?(port) when is_integer(port), do: port in @docker_ports

  @doc """
  Check if `port` is a Kubernetes API port.
  """
  @spec kubernetes_port?(:inet.port_number()) :: boolean()
  def kubernetes_port?(port) when is_integer(port), do: port in @kubernetes_ports

  @doc """
  Check if `port` is a sensitive metrics port (always blocked).

  These ports expose sensitive host/network data and should never be proxied:
    * `host_metrics_port` (default `49_100`) — Node Exporter metrics
    * `wireguard_metrics_port` (default `49_586`) — WireGuard interface metrics
  """
  @spec metrics_port?(:inet.port_number()) :: boolean()
  def metrics_port?(port) when is_integer(port) do
    host_metrics_port = Application.get_env(:edge_agent, :host_metrics_port)
    wireguard_metrics_port = Application.get_env(:edge_agent, :wireguard_metrics_port)
    port in [host_metrics_port, wireguard_metrics_port]
  end

  @doc """
  Check if `host`/`port` is in the custom block list (user-configured).

  Supports two formats via `proxy_custom_blocked_hosts`:
    * Host only: `["badhost.com", "evil.net"]` — blocks all ports on that host
    * Host + port: `[{"internal-db.local", 5432}, {"cache.local", 6379}]`

  Also checks `proxy_blocked_ports` for additional port-only blocks.

  Hostname matches are case-insensitive and trailing-dot insensitive.
  """
  @spec custom_blocked?(String.t(), :inet.port_number()) :: boolean()
  def custom_blocked?(host, port) when is_binary(host) and is_integer(port) do
    custom_blocked_hosts = Application.get_env(:edge_agent, :proxy_custom_blocked_hosts, [])
    normalised = normalise_host(host)

    host_blocked =
      Enum.any?(custom_blocked_hosts, fn
        {blocked_host, blocked_port} ->
          normalise_host(blocked_host) == normalised and port == blocked_port

        blocked_host when is_binary(blocked_host) ->
          normalise_host(blocked_host) == normalised
      end)

    custom_blocked_ports = Application.get_env(:edge_agent, :proxy_blocked_ports, [])
    port_blocked = port in custom_blocked_ports

    host_blocked or port_blocked
  end

  @doc """
  Check if `host`/`port` is in the custom allow list (bypasses all other checks).
  Hostname matches are case-insensitive and trailing-dot insensitive.
  """
  @spec custom_allowed?(String.t(), :inet.port_number()) :: boolean()
  def custom_allowed?(host, port) when is_binary(host) and is_integer(port) do
    custom_allowed_hosts = Application.get_env(:edge_agent, :proxy_custom_allowed_hosts, [])
    normalised = normalise_host(host)

    Enum.any?(custom_allowed_hosts, fn
      {allowed_host, allowed_port} ->
        normalise_host(allowed_host) == normalised and port == allowed_port

      allowed_host when is_binary(allowed_host) ->
        normalise_host(allowed_host) == normalised
    end)
  end

  @doc """
  Get human-readable error message for a block reason.

  Production code paths render error messages via
  `EdgeAgent.ProxyServers.ErrorHandler.http_error_response/1` (HTTP) and
  `socks5_reply_code/1` (SOCKS5). This helper is kept for tests and any
  out-of-band reporting that needs a plain English string per reason.
  """
  @spec error_message(block_reason() | atom()) :: String.t()
  def error_message(reason) do
    case reason do
      :localhost_blocked ->
        "Access to localhost/loopback addresses is blocked for security"

      :metadata_service_blocked ->
        "Access to cloud metadata services is blocked for security"

      :link_local_blocked ->
        "Access to link-local addresses is blocked for security"

      :docker_port_blocked ->
        "Access to Docker API ports is blocked for security"

      :kubernetes_port_blocked ->
        "Access to Kubernetes API ports is blocked for security"

      :metrics_port_blocked ->
        "Access to metrics ports is blocked for security"

      :custom_blocked ->
        "Access to this destination is blocked by policy"

      :dns_resolution_failed ->
        "Hostname could not be resolved"

      :invalid_address ->
        "Invalid destination address"

      _ ->
        "Access blocked"
    end
  end

  # -------------------------------------------------------------------------
  # IP-tuple-domain checks (the source of truth for range matching)
  # -------------------------------------------------------------------------

  # IPv4 loopback: 127.0.0.0/8
  defp loopback_ip?({127, _, _, _}), do: true
  # 0.0.0.0 routes to loopback on Linux
  defp loopback_ip?({0, 0, 0, 0}), do: true
  # IPv6 loopback: ::1
  defp loopback_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback_ip?(_), do: false

  # IPv4 link-local: 169.254.0.0/16
  defp link_local_ip?({169, 254, _, _}), do: true
  # IPv6 link-local: fe80::/10 — first 10 bits are 1111111010
  defp link_local_ip?({a, _, _, _, _, _, _, _}) when a >= 0xFE80 and a <= 0xFEBF, do: true

  defp link_local_ip?(_), do: false

  defp metadata_ip?(ip), do: ip in @metadata_ips

  # Collapse IPv4-mapped IPv6 (::ffff:a.b.c.d) to the embedded IPv4 tuple, so
  # range checks treat `::ffff:127.0.0.1` identically to `127.0.0.1`.
  # See RFC 4291 §2.5.5.2.
  defp normalise_mapped({0, 0, 0, 0, 0, 0xFFFF, ab, cd}) do
    {Bitwise.bsr(ab, 8), Bitwise.band(ab, 0xFF), Bitwise.bsr(cd, 8), Bitwise.band(cd, 0xFF)}
  end

  defp normalise_mapped(ip), do: ip

  # -------------------------------------------------------------------------
  # Hostname-domain checks (only used when a host is not an IP literal)
  # -------------------------------------------------------------------------

  defp hostname_loopback?(host) do
    normalise_host(host) in @localhost_hostnames
  end

  defp hostname_metadata?(host) do
    normalise_host(host) in @metadata_hostnames
  end

  # Pre-DNS block check: any reason a hostname-and-port pair should be denied
  # without needing to resolve. Returns the reason atom or `nil` for "no
  # pre-DNS block — proceed to resolution and IP-level checks".
  defp host_port_block_reason(host, port) do
    cond do
      docker_port?(port) -> :docker_port_blocked
      kubernetes_port?(port) -> :kubernetes_port_blocked
      metrics_port?(port) -> :metrics_port_blocked
      hostname_loopback?(host) -> :localhost_blocked
      hostname_metadata?(host) -> :metadata_service_blocked
      custom_blocked?(host, port) -> :custom_blocked
      true -> nil
    end
  end

  # Lowercase + strip trailing dots. `Metadata.Google.Internal.` → `metadata.google.internal`.
  defp normalise_host(host) when is_binary(host) do
    host
    |> String.downcase()
    |> String.trim_trailing(".")
  end

  defp normalise_host(host) when is_list(host), do: host |> List.to_string() |> normalise_host()
  defp normalise_host(host) when is_atom(host), do: host |> Atom.to_string() |> normalise_host()

  # -------------------------------------------------------------------------
  # IP resolution + multi-record validation
  # -------------------------------------------------------------------------

  # Resolve a host string to a list of IP tuples.
  # If `host` is a literal IP, returns that IP without doing DNS.
  # Otherwise queries both A and AAAA records and returns all of them.
  defp resolve_any(host) do
    charlist = String.to_charlist(host)

    case :inet.parse_address(charlist) do
      {:ok, ip} ->
        {:ok, [normalise_mapped(ip)]}

      {:error, _} ->
        v4 = resolve_family(charlist, :inet)
        v6 = resolve_family(charlist, :inet6)

        case Enum.uniq(v4 ++ v6) do
          [] -> {:error, :nxdomain}
          ips -> {:ok, Enum.map(ips, &normalise_mapped/1)}
        end
    end
  end

  defp resolve_family(charlist, family) do
    case :inet.getaddrs(charlist, family) do
      {:ok, ips} -> ips
      {:error, _} -> []
    end
  end

  # Validate every resolved IP. If any IP is denied, deny the whole host —
  # a hostname with mixed safe/unsafe records is unsafe (the resolver may
  # return a different record on the next lookup).
  defp check_all_ips([], _host, _port), do: {:error, :dns_resolution_failed}

  defp check_all_ips(ips, host, port) do
    case Enum.find_value(ips, fn ip -> ip_block_reason(ip, port) end) do
      nil ->
        Logger.debug("Proxy destination allowed: #{host}:#{port}")
        {:ok, hd(ips)}

      reason ->
        Logger.warning("Proxy destination BLOCKED (#{reason}): #{host}:#{port} resolved to #{format_ips(ips)}")

        {:error, reason}
    end
  end

  defp ip_block_reason(ip, _port) do
    cond do
      loopback_ip?(ip) -> :localhost_blocked
      metadata_ip?(ip) -> :metadata_service_blocked
      link_local_ip?(ip) -> :link_local_blocked
      true -> nil
    end
  end

  # -------------------------------------------------------------------------
  # Address parsing helpers
  # -------------------------------------------------------------------------

  # Parse a string as an IP literal (v4 or v6), normalising IPv4-mapped IPv6.
  # Returns `{:ok, tuple}` for an IP, or `:error` for a hostname.
  defp parse_address(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} -> {:ok, normalise_mapped(ip)}
      {:error, _} -> :error
    end
  end

  defp format_ips(ips) do
    Enum.map_join(ips, ", ", fn ip -> ip |> :inet.ntoa() |> to_string() end)
  end
end
