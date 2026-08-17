# edge_admin/lib/edge_admin/proxy_servers/supervisor.ex
defmodule EdgeAdmin.ProxyServers.Supervisor do
  @moduledoc """
  Supervises the Admin proxy subsystem.

  The proxy listeners, the Admin-to-Admin tunnel listener, and the active
  tunnel registry share a lifecycle boundary while remaining independently
  restartable. A failure in this subsystem must not affect Admin clustering,
  edge-cluster gateways, or the HTTP API.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      EdgeAdmin.ProxyServers.Transport.TunnelRegistry,
      EdgeAdmin.ProxyServers.AdminTunnel.Listener,
      EdgeAdmin.ProxyServers
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
