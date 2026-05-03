# edge_admin/lib/edge_admin/admins/metadata/events.ex
defmodule EdgeAdmin.Admins.Metadata.Events do
  @moduledoc """
  Pub/sub surface for metadata-related events.

  Two topics, two audiences:

    * **Cluster-wide CRUD events** — node/cluster create/update/delete. Published
      by `EdgeAdmin.Nodes` and consumed by every peer admin's `Metadata`
      GenServer to trigger recomputation. Cross-admin, goes through Erlang
      distribution.

    * **Local recompute events** — `:recomputed` notifications. Published by
      `EdgeAdmin.Admins.Metadata` after a recomputation completes and consumed
      by this admin's `EdgeAdmin.EdgeClusters` GenServer to drive gateway
      reconciliation. Node-local, never leaves the VM.

  This module exists so call sites never construct topic strings or call
  `Phoenix.PubSub` directly. The transport is an implementation detail.
  """

  alias EdgeAdmin.Vpn

  @type crud_event ::
          :cluster_created
          | :cluster_deleted
          | :node_created
          | :node_updated
          | :node_deleted

  @type local_event :: :metadata_recomputed

  @pubsub EdgeAdmin.PubSub

  @doc """
  Publishes a CRUD event to every admin in this admin cluster.

  No-op if PubSub isn't running (e.g. inside a one-shot release task) — there
  are no peer admins listening on a transient script's BEAM node anyway.
  """
  @spec publish(crud_event()) :: :ok
  def publish(event) do
    if Process.whereis(@pubsub) do
      Phoenix.PubSub.broadcast(@pubsub, crud_topic(), event)
    end

    :ok
  end

  @doc """
  Publishes a recompute event to local subscribers only (this VM).
  """
  @spec publish_local(local_event()) :: :ok
  def publish_local(event) do
    Phoenix.PubSub.local_broadcast(@pubsub, local_topic(), event)
  end

  @doc """
  Subscribes the calling process to cluster-wide CRUD events.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, crud_topic())

  @doc """
  Subscribes the calling process to local recompute events.
  """
  @spec subscribe_local() :: :ok | {:error, term()}
  def subscribe_local, do: Phoenix.PubSub.subscribe(@pubsub, local_topic())

  defp crud_topic, do: "metadata:crud:#{Vpn.admin_cluster_name()}"

  defp local_topic do
    admin_name = Application.get_env(:edge_admin, :admin_name)
    "metadata:local:#{admin_name}"
  end
end
