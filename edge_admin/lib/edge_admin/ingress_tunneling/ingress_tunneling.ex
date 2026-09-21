# edge_admin/lib/edge_admin/ingress_tunneling/ingress_tunneling.ex
defmodule EdgeAdmin.IngressTunneling do
  @moduledoc """
  Public domain boundary for Core-managed Ingress Tunneling.

  The context owns Tunnel Client identities, their selected Ingress Node
  connections, provisioning artifacts, and Agent Ingress desired state.
  """

  alias EdgeAdmin.IngressTunneling.Forms.CreateTunnelClientForm
  alias EdgeAdmin.IngressTunneling.Forms.CreateTunnelConnectionForm
  alias EdgeAdmin.IngressTunneling.Resources.TunnelClients
  alias EdgeAdmin.IngressTunneling.Resources.TunnelConnections
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelClient
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelConnection

  @doc "Lists Tunnel Clients."
  @spec list_tunnel_clients(map()) :: {:ok, {[TunnelClient.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_tunnel_clients(params \\ %{}), to: TunnelClients, as: :list

  @doc "Gets a Tunnel Client by ID."
  @spec get_tunnel_client(String.t()) :: {:ok, TunnelClient.t()} | {:error, :not_found}
  defdelegate get_tunnel_client(id), to: TunnelClients, as: :get

  @doc "Creates an Admin-generated Tunnel Client identity."
  @spec create_tunnel_client() :: {:ok, TunnelClient.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_tunnel_client(), to: TunnelClients, as: :create

  @doc "Creates a Tunnel Client and its requested connections atomically."
  @spec create_tunnel_client_with_connections(map()) :: {:ok, TunnelClient.t()} | {:error, term()}
  def create_tunnel_client_with_connections(attrs \\ %{}) do
    with {:ok, params} <- CreateTunnelClientForm.changeset(attrs) do
      TunnelClients.create_with_connections(params["node_ids"])
    end
  end

  @doc "Deletes a Tunnel Client and its dependent Tunnel Connections."
  @spec delete_tunnel_client(TunnelClient.t()) :: {:ok, TunnelClient.t()} | {:error, Ecto.Changeset.t()}
  defdelegate delete_tunnel_client(tunnel_client), to: TunnelClients, as: :delete

  @doc "Lists Tunnel Connections."
  @spec list_tunnel_connections(map()) :: {:ok, {[TunnelConnection.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_tunnel_connections(params \\ %{}), to: TunnelConnections, as: :list

  @doc "Gets a Tunnel Connection by ID."
  @spec get_tunnel_connection(String.t()) :: {:ok, TunnelConnection.t()} | {:error, :not_found}
  defdelegate get_tunnel_connection(id), to: TunnelConnections, as: :get

  @doc "Validates and creates one Tunnel Connection for a Tunnel Client."
  @spec create_tunnel_connection(String.t(), map()) ::
          {:ok, TunnelConnection.t()}
          | {:error, :not_found | {:conflict, String.t()} | Ecto.Changeset.t()}
  def create_tunnel_connection(tunnel_client_id, attrs) when is_map(attrs) do
    with {:ok, params} <- CreateTunnelConnectionForm.changeset(attrs) do
      TunnelConnections.create(tunnel_client_id, params["node_id"])
    end
  end

  @doc "Deletes a Tunnel Connection."
  @spec delete_tunnel_connection(TunnelConnection.t()) :: {:ok, TunnelConnection.t()} | {:error, Ecto.Changeset.t()}
  defdelegate delete_tunnel_connection(tunnel_connection), to: TunnelConnections, as: :delete
end
