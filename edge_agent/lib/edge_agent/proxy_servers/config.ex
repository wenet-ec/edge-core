# edge_agent/lib/edge_agent/proxy_servers/config.ex
defmodule EdgeAgent.ProxyServers.Config do
  @moduledoc """
  Configuration for the proxy server (HTTP and SOCKS5).
  """

  def http_proxy_port, do: Application.get_env(:edge_agent, :http_proxy_port)
  def socks5_proxy_port, do: Application.get_env(:edge_agent, :socks5_proxy_port)

  def listen_address do
    Application.get_env(:edge_agent, :proxy_listen_address, {0, 0, 0, 0})
  end

  @doc """
  TCP connection timeout in ms. Default 2s.
  """
  def connection_timeout, do: get_timeout(:connection, 2_000)

  @doc """
  Client/target socket read timeout in ms. Default 10s.
  """
  def read_timeout, do: get_timeout(:read, 10_000)

  @doc """
  Idle timeout per recv call inside the forwarder. Default 5 min.
  """
  def recv_timeout, do: get_timeout(:recv, 300_000)

  @doc """
  Absolute ceiling on a single tunnel's lifetime (ms). Default 6h.
  Slowloris defence: bounds total duration regardless of per-read idle activity.
  """
  def tunnel_total_timeout, do: get_timeout(:tunnel_total, 21_600_000)

  @doc """
  Grace window for established tunnels to finish on graceful drain. Default 30s.
  """
  def drain_grace_timeout, do: get_timeout(:drain_grace, 30_000)

  @doc """
  Number of Ranch acceptor processes per listener. Default 100.
  """
  def num_acceptors, do: Application.get_env(:edge_agent, :proxy_num_acceptors, 100)

  defp get_timeout(key, default) do
    :edge_agent
    |> Application.get_env(:proxy_timeouts, [])
    |> Keyword.get(key, default)
  end
end
