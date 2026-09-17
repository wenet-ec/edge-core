# edge_admin/lib/edge_admin_mcp/tools/ingress_tunneling/get_tunnel_client.ex
defmodule EdgeAdminMcp.Tools.IngressTunneling.GetTunnelClient do
  @moduledoc """
  Get an Admin-managed Tunnel Client identity by ID.

  The response includes public identity metadata only; the private key is
  never returned.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.IngressTunneling
  alias EdgeAdmin.IngressTunneling.Views.TunnelClientView

  @impl true
  def title, do: "Get Tunnel Client"

  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :tunnel_client_id, {:required, :string}
  end

  @impl true
  def execute(%{tunnel_client_id: id}, frame) do
    case IngressTunneling.get_tunnel_client(id) do
      {:ok, tunnel_client} ->
        {:reply, Response.json(Response.tool(), TunnelClientView.render(tunnel_client)), frame}

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Tunnel Client #{id} not found"), frame}
    end
  end
end
