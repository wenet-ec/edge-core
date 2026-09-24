# edge_admin/lib/edge_admin/ingress_tunneling/ingress_tunneling.ex
defmodule EdgeAdmin.IngressTunneling do
  @moduledoc """
  Public domain boundary for Core-managed Ingress Tunneling.

  The context owns Tunnel Client identities, their selected Ingress Node
  connections, provisioning artifacts, and Agent Ingress desired state.
  """

  alias EdgeAdmin.GatewayRegistry
  alias EdgeAdmin.IngressTunneling.DesiredState
  alias EdgeAdmin.IngressTunneling.Forms.CreateTunnelClientForm
  alias EdgeAdmin.IngressTunneling.Forms.CreateTunnelConnectionForm
  alias EdgeAdmin.IngressTunneling.Resources.TunnelClientResources
  alias EdgeAdmin.IngressTunneling.Resources.TunnelConnectionResources
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelClient
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelConnection
  alias EdgeAdmin.IngressTunneling.Workers.DeliverIngressTunnelingWorker
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  require Logger

  @doc "Lists Tunnel Clients."
  @spec list_tunnel_clients(map()) :: {:ok, {[TunnelClient.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_tunnel_clients(params \\ %{}), to: TunnelClientResources, as: :list

  @doc "Gets a Tunnel Client by ID."
  @spec get_tunnel_client(String.t()) :: {:ok, TunnelClient.t()} | {:error, :not_found}
  defdelegate get_tunnel_client(id), to: TunnelClientResources, as: :get

  @doc "Creates a Tunnel Client and its requested connections atomically."
  @spec create_tunnel_client_with_connections(map()) :: {:ok, TunnelClient.t()} | {:error, term()}
  def create_tunnel_client_with_connections(attrs \\ %{}) do
    with {:ok, params} <- CreateTunnelClientForm.changeset(attrs) do
      case TunnelClientResources.create_with_connections(params["node_ids"]) do
        {:ok, tunnel_client} = result ->
          tunnel_client.tunnel_connections
          |> Enum.map(& &1.node_id)
          |> enqueue_deliveries()

          result

        error ->
          error
      end
    end
  end

  @doc "Deletes a Tunnel Client and enqueues desired-state updates for its Ingress nodes."
  @spec delete_tunnel_client(TunnelClient.t()) ::
          {:ok, TunnelClient.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def delete_tunnel_client(%TunnelClient{} = tunnel_client) do
    case TunnelClientResources.delete_with_connections(tunnel_client) do
      {:ok, {deleted, node_ids}} ->
        enqueue_deliveries(node_ids)
        {:ok, deleted}

      error ->
        error
    end
  end

  @doc "Lists Tunnel Connections."
  @spec list_tunnel_connections(map()) :: {:ok, {[TunnelConnection.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_tunnel_connections(params \\ %{}), to: TunnelConnectionResources, as: :list

  @doc "Gets a Tunnel Connection by ID."
  @spec get_tunnel_connection(String.t()) :: {:ok, TunnelConnection.t()} | {:error, :not_found}
  defdelegate get_tunnel_connection(id), to: TunnelConnectionResources, as: :get

  @doc "Validates and creates one Tunnel Connection for a Tunnel Client."
  @spec create_tunnel_connection(String.t(), map()) ::
          {:ok, TunnelConnection.t()}
          | {:error, :not_found | {:conflict, String.t()} | Ecto.Changeset.t()}
  def create_tunnel_connection(tunnel_client_id, attrs) when is_map(attrs) do
    with {:ok, params} <- CreateTunnelConnectionForm.changeset(attrs) do
      case TunnelConnectionResources.create_for_ingress(tunnel_client_id, params["node_id"]) do
        {:ok, tunnel_connection} = result ->
          enqueue_deliveries([tunnel_connection.node_id])
          result

        error ->
          error
      end
    end
  end

  @doc "Deletes a Tunnel Connection."
  @spec delete_tunnel_connection(TunnelConnection.t()) ::
          {:ok, TunnelConnection.t()} | {:error, Ecto.Changeset.t()}
  def delete_tunnel_connection(%TunnelConnection{} = tunnel_connection) do
    case TunnelConnectionResources.delete(tunnel_connection) do
      {:ok, deleted} = result ->
        enqueue_deliveries([deleted.node_id])
        result

      error ->
        error
    end
  end

  @spec deliver_ingress_tunneling(String.t()) :: :ok | {:error, term()}
  def deliver_ingress_tunneling(node_id) do
    case {Repo.get(Node, node_id), DesiredState.build(node_id)} do
      {nil, {:error, :not_found}} ->
        :ok

      {%Node{} = node, {:ok, desired_state}} ->
        node = Repo.preload(node, :cluster)

        with {:ok, gateway} <- GatewayRegistry.resolve_node(node),
             {:ok, :sent} <- GatewayRegistry.deliver_ingress_tunneling(gateway, node, desired_state) do
          :ok
        end

      {_, {:error, :not_found}} ->
        :ok
    end
  end

  defp enqueue_deliveries(node_ids) do
    Enum.each(node_ids, fn node_id ->
      worker = DeliverIngressTunnelingWorker.new(%{node_id: node_id})

      case Oban.insert(worker) do
        {:ok, _job} -> :ok
        {:error, reason} -> Logger.error("Failed to enqueue Ingress Tunneling delivery: #{inspect(reason)}")
      end
    end)
  end
end
