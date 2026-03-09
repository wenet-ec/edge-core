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
  Default: 5000ms (5 seconds)
  """
  def connection_timeout do
    get_timeout(:connection, 5_000)
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

  defp get_timeout(key, default) do
    :edge_admin
    |> Application.get_env(:proxy_timeouts, [])
    |> Keyword.get(key, default)
  end
end
