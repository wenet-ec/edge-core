# edge_agent/lib/edge_agent_proxy/supervisor.ex
defmodule EdgeAgentProxy.Supervisor do
  @moduledoc """
  Supervises the Agent proxy subsystem.

  The tunnel registry and HTTP/SOCKS5 proxy manager share a lifecycle
  boundary while remaining independently restartable. Proxy failures must
  not affect the Agent's SSH, metrics, bootstrap, or VPN services.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      EdgeAgentProxy.Transport.TunnelRegistry,
      EdgeAgentProxy
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
