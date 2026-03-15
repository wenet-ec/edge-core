# edge_agent/lib/edge_agent/lan/mdns.ex
defmodule EdgeAgent.Lan.Mdns do
  @moduledoc """
  Advertises the agent on the local network via mDNS.

  On startup, reads the node identity from Settings and tells MdnsLite to
  advertise two names:

  - `{node_id}.local` — the stable resolvable hostname for this node.
    Any device on the same subnet can reach the agent by this name.
  - `_edgecore._tcp.local` — service type record used by agents to
    discover each other (active in v3 LAN clustering).

  The node_id is determined during Bootstrap (step 1) and persisted in
  SQLite before this process starts, so `Settings.get_node_id/0` is
  always populated by the time `init/1` runs.
  """

  use GenServer

  alias EdgeAgent.Settings

  require Logger

  @service_id :edge_agent

  # =============================================================================
  # Public API
  # =============================================================================

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # =============================================================================
  # GenServer Callbacks
  # =============================================================================

  @impl true
  def init(_opts) do
    node_id = Settings.get_node_id()

    if node_id do
      hostname = "node-#{node_id}"
      port = Application.get_env(:edge_agent, :http_port, 44_000)

      MdnsLite.set_hosts([hostname])
      MdnsLite.add_mdns_service(%{id: @service_id, protocol: "edge_agent", transport: "tcp", port: port})
      Logger.info("mDNS: advertising as #{hostname}.local on port #{port}")
      {:ok, %{node_id: node_id, hostname: hostname}}
    else
      Logger.error("mDNS: node_id not set in Settings — skipping mDNS advertisement")
      {:ok, %{node_id: nil, hostname: nil}}
    end
  end
end
