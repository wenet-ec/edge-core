# edge_admin/lib/edge_admin/edge_clusters/supervisor.ex
defmodule EdgeAdmin.EdgeClusters.Supervisor do
  @moduledoc """
  DynamicSupervisor for Gateway processes.

  This is a simple supervisor that manages Gateway child processes.
  The actual coordination logic (listening to events, diffing state, etc.)
  lives in EdgeAdmin.EdgeClusters GenServer.

  Gateways are supervised with `:transient` restart strategy - they should
  only restart on abnormal exits, not on normal shutdown.
  """

  use DynamicSupervisor

  require Logger

  # ===========================================================================
  # Client API
  # ===========================================================================

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ===========================================================================
  # DynamicSupervisor Callbacks
  # ===========================================================================

  @impl true
  def init(_opts) do
    Logger.info("EdgeClusters.Supervisor starting")
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
