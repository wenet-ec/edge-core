# edge_agent/lib/edge_agent/lan/mdns.ex
defmodule EdgeAgent.Lan.Mdns do
  @moduledoc """
  Advertises the agent on the local network via mDNS.

  At boot, reads the node identity from Settings and registers two records
  with `MdnsLite`:

  - `node-{node_id}.local` — the stable resolvable hostname for this node.
    Any device on the same subnet can reach the agent by this name.
  - `_edge_core._tcp.local` — service type record used by agents and other
    LAN clients to discover edge agents on the same subnet.

  This is a one-shot Task. `MdnsLite` keeps its own state in
  `MdnsLite.TableServer`, so the Task configures records and exits while mDNS
  continues advertising. Bootstrap persists the node ID before this Task starts;
  `run/0` raises if that supervision invariant is broken.
  """

  alias EdgeAgent.Settings

  require Logger

  @service_id :edge_core

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
    port = Application.fetch_env!(:edge_agent, :agent_api_port)

    MdnsLite.set_hosts([hostname])

    MdnsLite.add_mdns_service(%{
      id: @service_id,
      instance_name: hostname,
      protocol: "edge_core",
      transport: "tcp",
      port: port
    })

    Logger.info("mDNS: advertising as #{hostname}.local on port #{port}")
    :ok
  end
end
