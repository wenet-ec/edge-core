# edge_agent/lib/edge_agent/lan/mdns.ex
defmodule EdgeAgent.Lan.Mdns do
  @moduledoc """
  Advertises the agent on the local network via mDNS.

  At boot, reads the node identity from Settings and registers two records
  with `MdnsLite`:

  - `node-{node_id}.local` — the stable resolvable hostname for this node.
    Any device on the same subnet can reach the agent by this name.
  - `_edge_agent._tcp.local` — service type record used by agents and other
    LAN clients to discover edge agents on the same subnet.

  ## Process model

  This module is a **one-shot Task**, not a long-lived GenServer. `MdnsLite`
  owns its own state in `MdnsLite.TableServer` (part of `:mdns_lite`'s
  supervision tree); the calls below are fire-and-forget configuration. Once
  the Task exits, mDNS keeps advertising on its own. `restart: :transient`
  ensures a crash during configuration is still surfaced by the supervisor,
  while a normal exit doesn't cause needless restarts.

  ## node_id invariant

  The node_id is determined during Bootstrap (step 1) and persisted in
  SQLite before this Task starts, so `Settings.get_node_id/0` is always
  populated by the time `run/0` runs. If it isn't, that's a bug in the
  supervision order — `run/0` raises rather than silently advertising
  nothing.
  """

  alias EdgeAgent.Settings

  require Logger

  @service_id :edge_agent

  @doc false
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {Task, :start_link, [&__MODULE__.run/0]},
      restart: :transient,
      type: :worker
    }
  end

  @doc """
  Configures `MdnsLite` to advertise this node, then returns. Intended to be
  run once at boot via the supervisor's child_spec; not meant to be called
  directly by application code.
  """
  @spec run() :: :ok
  def run do
    node_id =
      Settings.get_node_id() ||
        raise "mDNS: node_id missing from Settings — Bootstrap must run before EdgeAgent.Lan.Mdns"

    hostname = "node-#{node_id}"
    port = Application.fetch_env!(:edge_agent, :api_port)

    MdnsLite.set_hosts([hostname])

    MdnsLite.add_mdns_service(%{
      id: @service_id,
      instance_name: hostname,
      protocol: "edge_agent",
      transport: "tcp",
      port: port
    })

    Logger.info("mDNS: advertising as #{hostname}.local on port #{port}")
    :ok
  end
end
