# edge_admin/lib/edge_admin/proxy_servers/config.ex
defmodule EdgeAdmin.ProxyServers.Config do
  @moduledoc """
  Configuration for the proxy server (HTTP and SOCKS5).
  """

  @doc """
  Get HTTP proxy port from environment or config.
  """
  def http_proxy_port do
    Application.get_env(:edge_admin, :http_proxy_port)
  end

  @doc """
  Get SOCKS5 proxy port from environment or config.
  """
  def socks5_proxy_port do
    Application.get_env(:edge_admin, :socks5_proxy_port)
  end

  @doc """
  Get proxy listen address as a tuple for Ranch.
  """
  def listen_address do
    {0, 0, 0, 0}
  end

  @doc """
  Returns the TCP connection timeout in milliseconds.

  Used when establishing connections to target hosts.
  Default: 2000ms (2 seconds)
  """
  def connection_timeout do
    get_timeout(:connection, 2_000)
  end

  @doc """
  Returns the proxy handshake timeout in milliseconds.

  Used for SOCKS5 and HTTP proxy handshakes (multi-step operations).
  Default: 10000ms (10 seconds)
  """
  def handshake_timeout do
    get_timeout(:handshake, 10_000)
  end

  @doc """
  Returns the socket read timeout in milliseconds.

  Used for reading from client/target sockets.
  Default: 10000ms (10 seconds)
  """
  def read_timeout do
    get_timeout(:read, 10_000)
  end

  @doc """
  Returns the inactivity recv timeout for forwarding loops in milliseconds.

  Applied to each :gen_tcp.recv call in the forwarding loop. Closes half-open
  connections after this period of inactivity.
  Default: 300000ms (5 minutes)
  """
  def recv_timeout do
    get_timeout(:recv, 300_000)
  end

  @doc """
  Returns the number of Ranch acceptor processes for each proxy listener.

  Default: 100
  """
  def num_acceptors do
    Application.get_env(:edge_admin, :proxy_num_acceptors, 100)
  end

  @doc """
  Returns the absolute cap on a single tunnel's lifetime in milliseconds.

  Distinct from `recv_timeout/0` (idle cap). A trickle of activity can hold
  a tunnel open indefinitely against `recv_timeout`; this ceiling bounds the
  total duration as a slowloris defence.

  Default: 6h (21_600_000ms). Set to a very large value to effectively disable.
  """
  def tunnel_total_timeout do
    get_timeout(:tunnel_total, 21_600_000)
  end

  @doc """
  Maximum number of HTTP requests served over a single keep-alive connection.

  Default: 100. After this many requests, the handler closes the connection.
  """
  def max_keepalive_requests do
    Application.get_env(:edge_admin, :proxy_max_keepalive_requests, 100)
  end

  @doc """
  Grace period in milliseconds for established tunnels to finish during
  graceful drain (deploy / shutdown). Handlers receive `{:drain, grace_ms}`
  when shutdown starts; after the grace, surviving tunnels are force-closed.

  Default: 30_000 (30s).
  """
  def drain_grace_timeout do
    get_timeout(:drain_grace, 30_000)
  end

  defp get_timeout(key, default) do
    :edge_admin
    |> Application.get_env(:proxy_timeouts, [])
    |> Keyword.get(key, default)
  end
end
