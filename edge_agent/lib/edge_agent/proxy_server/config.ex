# edge_agent/lib/edge_agent/proxy_server/config.ex
defmodule EdgeAgent.ProxyServer.Config do
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
end
