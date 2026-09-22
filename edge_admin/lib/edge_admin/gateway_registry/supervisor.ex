# edge_admin/lib/edge_admin/gateway_registry/supervisor.ex
defmodule EdgeAdmin.GatewayRegistry.Supervisor do
  @moduledoc """
  Dynamic supervisor for per-cluster Gateway processes.

  Gateway children use `:transient` restart so normal assignment removal does
  not restart them.
  """

  use DynamicSupervisor

  require Logger

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("GatewayRegistry.Supervisor starting")
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
