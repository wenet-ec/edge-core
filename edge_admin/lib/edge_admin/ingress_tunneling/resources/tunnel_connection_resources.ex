# edge_admin/lib/edge_admin/ingress_tunneling/resources/tunnel_connection_resources.ex
defmodule EdgeAdmin.IngressTunneling.Resources.TunnelConnectionResources do
  @moduledoc """
  Tunnel Connection persistence and per-Ingress address allocation.
  """

  import Ecto.Query, warn: false

  alias Ecto.Query.CastError
  alias EdgeAdmin.IngressTunneling.Addressing
  alias EdgeAdmin.IngressTunneling.Checks.IngressIdentityCheck
  alias EdgeAdmin.IngressTunneling.Persistence
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelClient
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelConnection
  alias EdgeAdmin.Nodes
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

  @doc "Inserts a Tunnel Connection from validated and allocated attributes."
  @spec create(map()) ::
          {:ok, TunnelConnection.t()}
          | {:error, {:conflict, String.t()} | Ecto.Changeset.t()}
  def create(attrs) do
    attrs
    |> then(&TunnelConnection.changeset(%TunnelConnection{}, &1))
    |> Repo.insert()
    |> Repo.normalize_conflict([:tunnel_client_id, :node_id, :tunnel_ipv4_address, :tunnel_ipv6_address])
  end

  @doc "Creates a Tunnel Connection for an Ingress and allocates its address pairs."
  @spec create_for_ingress(String.t(), String.t()) ::
          {:ok, TunnelConnection.t()}
          | {:error, :not_found | {:conflict, String.t()} | Ecto.Changeset.t()}
  def create_for_ingress(tunnel_client_id, node_id) do
    Repo.transaction_with_write_lock(fn ->
      with %TunnelClient{} <- Persistence.lock_tunnel_client(tunnel_client_id),
           %Node{} = ingress <- Nodes.lock_node(node_id),
           :ok <- IngressIdentityCheck.check(ingress),
           {:ok, addresses} <- allocate_addresses(ingress.id),
           {:ok, tunnel_connection} <-
             create(Map.merge(addresses, %{tunnel_client_id: tunnel_client_id, node_id: ingress.id})) do
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
end
