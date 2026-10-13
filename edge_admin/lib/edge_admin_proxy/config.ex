# edge_admin/lib/edge_admin_proxy/config.ex
defmodule EdgeAdminProxy.Config do
  @moduledoc """
  Configuration for the proxy server (HTTP and SOCKS5).
  """

  def http_proxy_port do
    Application.get_env(:edge_admin, :admin_http_proxy_port)
  end

  def socks5_proxy_port do
    Application.get_env(:edge_admin, :admin_socks5_proxy_port)
  end

  def listen_address do
    {0, 0, 0, 0, 0, 0, 0, 0}
  end

  @doc "Socket options that force a single IPv6 wildcard listener to accept IPv4-mapped clients too."
  def listen_socket_options do
    [:inet6, {:ipv6_v6only, false}]
  end

  @doc """
  Returns the TCP connection timeout in milliseconds.

  Used when establishing connections to target hosts.
  Configured by `PROXY_CONNECTION_TIMEOUT_MS`.
  """
  def connection_timeout do
    get_timeout(:connection)
  end

  @doc """
  Returns the proxy handshake timeout in milliseconds.

  Used for SOCKS5 and HTTP proxy handshakes (multi-step operations).
  Configured by `PROXY_HANDSHAKE_TIMEOUT_MS`.
  """
  def handshake_timeout do
    get_timeout(:handshake)
  end

  @doc """
  Returns the socket read timeout in milliseconds.

  Used for reading from client/target sockets.
  Configured by `PROXY_READ_TIMEOUT_MS`.
  """
  def read_timeout do
    get_timeout(:read)
  end

  @doc """
  Returns the inactivity recv timeout for forwarding loops in milliseconds.

  Applied to each :gen_tcp.recv call in the forwarding loop. Closes half-open
  connections after this period of inactivity.
  Configured by `PROXY_RECV_TIMEOUT_MS`.
  """
  def recv_timeout do
    get_timeout(:recv)
  end

  @doc """
  Returns the number of Ranch acceptor processes for each proxy listener.

  Configured by `PROXY_NUM_ACCEPTORS`.
  """
  def num_acceptors, do: Application.fetch_env!(:edge_admin, :proxy_num_acceptors)

  @doc """
  Returns the absolute cap on a single tunnel's lifetime in milliseconds.

  Distinct from `recv_timeout/0` (idle cap). A trickle of activity can hold
  a tunnel open indefinitely against `recv_timeout`; this ceiling bounds the
  total duration as a slowloris defence.

  Configured by `PROXY_TUNNEL_TOTAL_TIMEOUT_MS`. Set to a very large value
  to effectively disable.
  """
  def tunnel_total_timeout do
    get_timeout(:tunnel_total)
  end

  @doc """
  Grace period in milliseconds for established tunnels to finish during
  graceful drain (deploy / shutdown). Handlers receive `{:drain, grace_ms}`
  when shutdown starts; after the grace, surviving tunnels are force-closed.

  Configured by `PROXY_DRAIN_GRACE_TIMEOUT_MS`.
  """
  def drain_grace_timeout do
    get_timeout(:drain_grace)
  end

  defp get_timeout(key) do
    :edge_admin
    |> Application.fetch_env!(:proxy_timeouts)
    |> Keyword.fetch!(key)
  end
end
