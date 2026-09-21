# edge_admin/lib/edge_admin/ingress_tunneling/resources/tunnel_connections.ex
defmodule EdgeAdmin.IngressTunneling.Resources.TunnelConnections do
  @moduledoc """
  Owns Tunnel Connection persistence and per-Ingress address allocation.

  Creating or deleting a row intentionally has no Agent synchronization side
  effect yet. The database is the desired authorization state; Agent delivery
  will be added as a separate reconciliation workflow.
  """

  import Ecto.Query, warn: false

  alias Ecto.Query.CastError
  alias EdgeAdmin.IngressTunneling.Addressing
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelClient
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelConnection
  alias EdgeAdmin.Nodes.Schemas.Node
  alias EdgeAdmin.Repo

  @spec list(map()) :: {:ok, {[TunnelConnection.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list(params \\ %{}) do
    Flop.validate_and_run(TunnelConnection, EdgeAdmin.RequestParser.parse(params),
      for: TunnelConnection,
      replace_invalid_params: true
    )
  end

  @spec get(String.t()) :: {:ok, TunnelConnection.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(TunnelConnection, id) do
      nil -> {:error, :not_found}
      tunnel_connection -> {:ok, tunnel_connection}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc "Creates a Tunnel Connection and allocates its Ingress and Tunnel IPv4/IPv6 address pairs."
  @spec create(String.t(), String.t()) ::
          {:ok, TunnelConnection.t()}
          | {:error, :not_found | {:conflict, String.t()} | Ecto.Changeset.t()}
  def create(tunnel_client_id, node_id) do
    Repo.transaction_with_write_lock(fn ->
      with %TunnelClient{} <- Repo.get(TunnelClient, tunnel_client_id),
           %Node{} = ingress <- lock_ingress_node(node_id),
           :ok <- ensure_ingress_identity(ingress),
           {:ok, addresses} <- allocate_addresses(ingress.id),
           {:ok, tunnel_connection} <- insert_connection(tunnel_client_id, ingress.id, addresses) do
        tunnel_connection
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  rescue
    CastError -> {:error, :not_found}
  end

  @spec delete(TunnelConnection.t()) :: {:ok, TunnelConnection.t()} | {:error, Ecto.Changeset.t()}
  def delete(%TunnelConnection{} = tunnel_connection), do: Repo.delete(tunnel_connection)

  defp lock_ingress_node(node_id) do
    query = from(node in Node, where: node.id == ^node_id)

    query =
      if Repo.__adapter__() == Ecto.Adapters.Postgres do
        from(node in query, lock: "FOR UPDATE")
      else
        query
      end

    Repo.one(query)
  end

  defp ensure_ingress_identity(%Node{ingress_public_key: key}) when is_binary(key) and key != "", do: :ok

  defp ensure_ingress_identity(_node) do
    {:error, {:conflict, "node has no Ingress WireGuard identity"}}
  end

  defp allocate_addresses(node_id) do
    {ipv4_addresses, ipv6_addresses} =
      from(connection in TunnelConnection,
        where: connection.node_id == ^node_id,
        select: {connection.tunnel_ipv4_address, connection.tunnel_ipv6_address}
      )
      |> Repo.all()
      |> Enum.unzip()

    Addressing.allocate(ipv4_addresses, ipv6_addresses)
  end

  defp insert_connection(tunnel_client_id, node_id, addresses) do
    addresses
    |> Map.merge(%{tunnel_client_id: tunnel_client_id, node_id: node_id})
    |> then(&TunnelConnection.changeset(%TunnelConnection{}, &1))
    |> Repo.insert()
    |> Repo.normalize_conflict([:tunnel_client_id, :node_id, :tunnel_ipv4_address, :tunnel_ipv6_address])
  end
end
