# edge_admin/lib/edge_admin_proxy/supervisor.ex
defmodule EdgeAdminProxy.Supervisor do
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
      EdgeAdminProxy.Transport.TunnelRegistry,
      EdgeAdminProxy.AdminTunnel.Listener,
      EdgeAdminProxy
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
