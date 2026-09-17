# edge_admin/lib/edge_admin/ingress_tunneling/ingress_tunneling.ex
defmodule EdgeAdmin.IngressTunneling do
  @moduledoc """
  Public domain boundary for Core-managed Ingress Tunneling.

  The context owns Tunnel Client identities, their selected Ingress Node
  connections, provisioning artifacts, and Agent Ingress desired state.
  """

  alias EdgeAdmin.IngressTunneling.Resources.TunnelClients
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelClient

  @doc "Lists Tunnel Clients."
  @spec list_tunnel_clients(map()) :: {:ok, {[TunnelClient.t()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  defdelegate list_tunnel_clients(params \\ %{}), to: TunnelClients, as: :list

  @doc "Gets a Tunnel Client by ID."
  @spec get_tunnel_client(String.t()) :: {:ok, TunnelClient.t()} | {:error, :not_found}
  defdelegate get_tunnel_client(id), to: TunnelClients, as: :get

  @doc "Creates an Admin-generated Tunnel Client identity."
  @spec create_tunnel_client() :: {:ok, TunnelClient.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_tunnel_client(), to: TunnelClients, as: :create

  @doc "Deletes a Tunnel Client and its dependent Tunnel Connections."
  @spec delete_tunnel_client(TunnelClient.t()) :: {:ok, TunnelClient.t()} | {:error, Ecto.Changeset.t()}
  defdelegate delete_tunnel_client(tunnel_client), to: TunnelClients, as: :delete
end
