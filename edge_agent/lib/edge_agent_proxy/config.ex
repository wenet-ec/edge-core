# edge_agent/lib/edge_agent_proxy/config.ex
defmodule EdgeAgentProxy.Config do
  @moduledoc """
  Configuration for the proxy server (HTTP and SOCKS5).

  Categories:

  - **Ports**: `http_proxy_port/0`, `socks5_proxy_port/0`, `listen_address/0`
  - **Per-operation timeouts** (read from `:proxy_timeouts` keyword):
    `connection_timeout/0`, `read_timeout/0`, `recv_timeout/0`,
    `tunnel_total_timeout/0`
  - **Lifecycle**: `drain_grace_timeout/0` for graceful shutdown
  - **Capacity**: `num_acceptors/0` (Ranch acceptor pool size per listener)

  Runtime values are configured in `config/runtime.exs`.
  """

  def http_proxy_port, do: Application.get_env(:edge_agent, :agent_http_proxy_port)
  def socks5_proxy_port, do: Application.get_env(:edge_agent, :agent_socks5_proxy_port)

  def listen_address do
    Application.fetch_env!(:edge_agent, :proxy_listen_address)
  end

  def listen_socket_options, do: [:inet6, {:ipv6_v6only, false}]

  @doc """
  TCP connection timeout in ms.
  """
  def connection_timeout, do: get_timeout(:connection)

  @doc """
  Client/target socket read timeout in ms.
  """
  def read_timeout, do: get_timeout(:read)

  @doc """
  Idle timeout per recv call inside the forwarder.
  """
  def recv_timeout, do: get_timeout(:recv)

  @doc """
  Absolute ceiling on a single tunnel's lifetime (ms). Configurable via
  `PROXY_TUNNEL_TOTAL_TIMEOUT_MS`.

  Slowloris defence: bounds total duration regardless of per-read idle activity.
  Set to a very large value to effectively disable.
  """
  def tunnel_total_timeout, do: get_timeout(:tunnel_total)

  @doc """
  Grace window for established tunnels to finish on graceful drain.
  Configured via `PROXY_DRAIN_GRACE_TIMEOUT_MS`.
  """
  def drain_grace_timeout, do: get_timeout(:drain_grace)

  @doc """
  Number of Ranch acceptor processes per listener. Configurable via
  `PROXY_NUM_ACCEPTORS`.
  """
  def num_acceptors, do: Application.fetch_env!(:edge_agent, :proxy_num_acceptors)

  defp get_timeout(key) do
    :edge_agent
    |> Application.fetch_env!(:proxy_timeouts)
    |> Keyword.fetch!(key)
  end
end
