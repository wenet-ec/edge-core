# edge_admin/lib/edge_admin/ingress_tunneling/resources/tunnel_clients.ex
defmodule EdgeAdmin.IngressTunneling.Resources.TunnelClients do
  @moduledoc """
  Owns persistence and generated identity creation for Tunnel Clients.

  A Tunnel Client is immutable after creation. Connection provisioning and
  Agent Ingress synchronization are deliberately separate workflows.
  """

  alias Ecto.Query.CastError
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelClient
  alias EdgeAdmin.IngressTunneling.WireGuard
  alias EdgeAdmin.Repo

  @doc "Lists Tunnel Clients with pagination and supported timestamp sorting."
  @spec list(map()) :: {:ok, {[TunnelClient.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list(params \\ %{}) do
    Flop.validate_and_run(TunnelClient, EdgeAdmin.RequestParser.parse(params),
      for: TunnelClient,
      replace_invalid_params: true
    )
  end

  @doc "Gets a Tunnel Client by ID."
  @spec get(String.t()) :: {:ok, TunnelClient.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(TunnelClient, id) do
      nil -> {:error, :not_found}
      tunnel_client -> {:ok, tunnel_client}
    end
  rescue
    CastError -> {:error, :not_found}
  end

  @doc "Generates and persists a new X25519 WireGuard Tunnel Client identity."
  @spec create() :: {:ok, TunnelClient.t()} | {:error, Ecto.Changeset.t()}
  def create do
    attrs = WireGuard.generate_keypair()

    %TunnelClient{}
    |> TunnelClient.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Deletes a Tunnel Client and its dependent Tunnel Connections."
  @spec delete(TunnelClient.t()) :: {:ok, TunnelClient.t()} | {:error, Ecto.Changeset.t()}
  def delete(%TunnelClient{} = tunnel_client), do: Repo.delete(tunnel_client)
end
