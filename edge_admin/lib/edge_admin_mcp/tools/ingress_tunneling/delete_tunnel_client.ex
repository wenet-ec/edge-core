# edge_admin/lib/edge_admin_mcp/tools/ingress_tunneling/delete_tunnel_client.ex
defmodule EdgeAdminMcp.Tools.IngressTunneling.DeleteTunnelClient do
  @moduledoc """
  Permanently delete an Admin-managed Tunnel Client and its dependent Tunnel
  Connections. Its private key is never returned by the tool.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.IngressTunneling

  @impl true
  def title, do: "Delete Tunnel Client"

  @impl true
  def annotations, do: %{"destructiveHint" => true, "idempotentHint" => false, "openWorldHint" => false}

  schema do
    field :tunnel_client_id, {:required, :string}
  end

  @impl true
  def execute(%{tunnel_client_id: id}, frame) do
    with {:ok, tunnel_client} <- IngressTunneling.get_tunnel_client(id),
         {:ok, _tunnel_client} <- IngressTunneling.delete_tunnel_client(tunnel_client) do
      {:reply, Response.json(Response.tool(), %{deleted: true, id: id}), frame}
    else
      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Tunnel Client #{id} not found"), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
