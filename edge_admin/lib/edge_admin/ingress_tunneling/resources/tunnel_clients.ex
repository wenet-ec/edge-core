# edge_admin/lib/edge_admin/ingress_tunneling/resources/tunnel_clients.ex
defmodule EdgeAdmin.IngressTunneling.Resources.TunnelClients do
  @moduledoc """
  Owns persistence and generated identity creation for Tunnel Clients.

  A Tunnel Client is immutable after creation. Agent Ingress synchronization
  is deliberately separate from this persistence workflow.
  """

  alias Ecto.Query.CastError
  alias EdgeAdmin.IngressTunneling.Resources.TunnelConnections
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelClient
  alias EdgeAdmin.IngressTunneling.WireGuard
  alias EdgeAdmin.Repo

  @spec list(map()) :: {:ok, {[TunnelClient.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list(params \\ %{}) do
    case Flop.validate_and_run(TunnelClient, EdgeAdmin.RequestParser.parse(params),
           for: TunnelClient,
           replace_invalid_params: true
         ) do
      {:ok, {tunnel_clients, meta}} ->
        {:ok, {Repo.preload(tunnel_clients, :tunnel_connections), meta}}

      error ->
        error
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

  @spec create() :: {:ok, TunnelClient.t()} | {:error, Ecto.Changeset.t()}
  def create do
    attrs = WireGuard.generate_keypair()

    %TunnelClient{}
    |> TunnelClient.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Creates a Tunnel Client and its requested connections atomically."
  @spec create_with_connections([String.t()]) :: {:ok, TunnelClient.t()} | {:error, term()}
  def create_with_connections(node_ids) when is_list(node_ids) do
    Repo.transaction_with_write_lock(fn ->
      with {:ok, tunnel_client} <- create(),
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
      case TunnelConnections.create(tunnel_client_id, node_id) do
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
end
