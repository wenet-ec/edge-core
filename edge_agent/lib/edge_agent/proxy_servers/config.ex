# edge_agent/lib/edge_agent/proxy_server/config.ex
defmodule EdgeAgent.ProxyServers.Config do
  @moduledoc """
  Configuration for the proxy server (HTTP and SOCKS5).
  """

  @doc """
  Get HTTP proxy port from environment or config.
  """
  def http_proxy_port do
    Application.get_env(:edge_agent, :http_proxy_port)
  end

  @doc """
  Get SOCKS5 proxy port from environment or config.
  """
  def socks5_proxy_port do
    Application.get_env(:edge_agent, :socks5_proxy_port)
  end

  @doc """
  Get proxy listen address as a tuple for Ranch.
  """
  def listen_address do
    Application.get_env(:edge_agent, :proxy_listen_address, {0, 0, 0, 0})
  end

  @doc """
  Returns the TCP connection timeout in milliseconds.

  Used when establishing connections to target hosts.
  Default: 30000ms (30 seconds)
  """
  def connection_timeout do
    get_timeout(:connection, 30_000)
  end

  @doc """
  Returns the socket read timeout in milliseconds.

  Used for reading from client/target sockets.
  Default: 10000ms (10 seconds)
  """
  def read_timeout do
    get_timeout(:read, 10_000)
  end

  defp get_timeout(key, default) do
    Application.get_env(:edge_agent, :proxy_timeouts, [])
    |> Keyword.get(key, default)
  end
end
