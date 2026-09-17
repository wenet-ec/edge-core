# edge_admin/lib/edge_admin_mcp/tools/ingress_tunneling/create_tunnel_client.ex
defmodule EdgeAdminMcp.Tools.IngressTunneling.CreateTunnelClient do
  @moduledoc """
  Generate and persist an Admin-owned Tunnel Client WireGuard identity.

  Tunnel Clients are immutable. The generated private key is encrypted at rest
  and is never returned by this tool or any other public Admin surface.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.IngressTunneling
  alias EdgeAdmin.IngressTunneling.Views.TunnelClientView

  @impl true
  def title, do: "Create Tunnel Client"

  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => false, "openWorldHint" => false}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    case IngressTunneling.create_tunnel_client() do
      {:ok, tunnel_client} ->
        {:reply, Response.json(Response.tool(), TunnelClientView.render(tunnel_client)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
