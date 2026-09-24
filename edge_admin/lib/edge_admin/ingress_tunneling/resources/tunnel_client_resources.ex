# edge_admin/lib/edge_admin/ingress_tunneling/resources/tunnel_client_resources.ex
defmodule EdgeAdmin.IngressTunneling.Resources.TunnelClientResources do
  @moduledoc """
  Persists Tunnel Clients and composes generated-keypair and nested-connection creation.
  """

  import Ecto.Query, warn: false

  alias Ecto.Query.CastError
  alias EdgeAdmin.IngressTunneling.Persistence
  alias EdgeAdmin.IngressTunneling.Resources.TunnelConnectionResources
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelClient
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelConnection
  alias EdgeAdmin.IngressTunneling.WireGuard
  alias EdgeAdmin.Repo

  @spec list(map()) :: {:ok, {[TunnelClient.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list(params \\ %{}) do
    with {:ok, {tunnel_clients, meta}} <-
           Flop.validate_and_run(TunnelClient, EdgeAdmin.RequestParser.parse(params),
             for: TunnelClient,
             replace_invalid_params: true
           ) do
      {:ok, {Repo.preload(tunnel_clients, :tunnel_connections), meta}}
    end
  end

  @spec get(String.t()) :: {:ok, TunnelClient.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(TunnelClient, id) do
      nil -> {:error, :not_found}
      tunnel_client -> {:ok, Repo.preload(tunnel_client, :tunnel_connections)}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc "Inserts a Tunnel Client from validated key attributes."
  @spec create(map()) :: {:ok, TunnelClient.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %TunnelClient{}
    |> TunnelClient.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Creates a Tunnel Client with an Admin-generated WireGuard keypair."
  @spec create_generated() :: {:ok, TunnelClient.t()} | {:error, Ecto.Changeset.t()}
  def create_generated, do: create(WireGuard.generate_keypair())

  @doc "Creates a Tunnel Client and its requested connections atomically."
  @spec create_with_connections([String.t()]) :: {:ok, TunnelClient.t()} | {:error, term()}
  def create_with_connections(node_ids) when is_list(node_ids) do
    Repo.transaction_with_write_lock(fn ->
      with {:ok, tunnel_client} <- create_generated(),
           {:ok, connections} <- create_connections(tunnel_client.id, node_ids) do
        %{tunnel_client | tunnel_connections: connections}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp create_connections(tunnel_client_id, node_ids) do
    node_ids
    |> Enum.reduce_while({:ok, []}, fn node_id, {:ok, connections} ->
      case TunnelConnectionResources.create_for_ingress(tunnel_client_id, node_id) do
        {:ok, connection} -> {:cont, {:ok, [connection | connections]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, connections} -> {:ok, Enum.reverse(connections)}
      error -> error
    end
  end

  @spec delete(TunnelClient.t()) :: {:ok, TunnelClient.t()} | {:error, Ecto.Changeset.t()}
  def delete(%TunnelClient{} = tunnel_client), do: Repo.delete(tunnel_client)

  @doc "Deletes a Tunnel Client and returns the Ingress node IDs whose desired state must be refreshed."
  @spec delete_with_connections(TunnelClient.t()) ::
          {:ok, {TunnelClient.t(), [String.t()]}} | {:error, :not_found | Ecto.Changeset.t()}
  def delete_with_connections(%TunnelClient{} = tunnel_client) do
    Repo.transaction_with_write_lock(fn ->
      case Persistence.lock_tunnel_client(tunnel_client.id) do
        nil ->
          Repo.rollback(:not_found)

        locked_client ->
          node_ids =
            Repo.all(
              from(connection in TunnelConnection,
                where: connection.tunnel_client_id == ^locked_client.id,
                select: connection.node_id
              )
            )

          case delete(locked_client) do
            {:ok, deleted} -> {deleted, node_ids}
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end
end
