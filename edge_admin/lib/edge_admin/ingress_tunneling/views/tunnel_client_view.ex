# edge_admin/lib/edge_admin/ingress_tunneling/views/tunnel_client_view.ex
defmodule EdgeAdmin.IngressTunneling.Views.TunnelClientView do
  @moduledoc """
  Canonical public render shape for Tunnel Clients.

  The private key is deliberately excluded from every public response.
  """

  alias EdgeAdmin.IngressTunneling.Schemas.TunnelClient

  @spec render(TunnelClient.t()) :: map()
  def render(%TunnelClient{} = tunnel_client) do
    %{
      id: tunnel_client.id,
      public_key: tunnel_client.public_key,
      inserted_at: tunnel_client.inserted_at,
      updated_at: tunnel_client.updated_at
    }
  end
end
